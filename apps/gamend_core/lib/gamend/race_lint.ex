defmodule Gamend.RaceLint do
  @moduledoc """
  Source checks for the shapes that race: a rule ("one per player", "pays
  once", "at most N", "only while pending") checked by a read and kept by a
  write that does not look again. `mix gamend.race.lint` runs them.

  Each check reads one function at a time and asks whether it writes in a
  way only an earlier read made safe, with nothing in the same function that
  makes the pair atomic: `Gamend.Repo.compare_and_set/2`, `Repo.lock_rows/2`,
  `Gamend.Lock.serialize/3` or `exclusive/3`, `Gamend.Lock.Local.trans/2`.
  The rule they enforce is AGENTS.md, "Locks".

  A call to a function of the same file that is itself guarded counts as a
  guard too (`with_pair_lock/3` wrapping `Lock.serialize/3`), through any
  number of such helpers.

  They are heuristics, and say so: a function that only ever runs inside its
  caller's lock reads as unguarded here. Mark it, with the reason, anywhere
  inside the function:

      # race-safe: runs inside join_lobby's (:lobby, id) lock

  The marker is the point. It puts the reasoning where the next person
  changing the function will read it, and the lint keeps asking for one
  whenever a new function has the shape.

  ## Checks

  - **RACE1-transition-by-struct** — a status, state or seat column (`status`,
    `lobby_id`, `resolved_at`, …) written by `Repo.update` on a changeset of a
    struct. Whatever the struct said when it was read, two callers can both
    have read it. Write the transition as `compare_and_set/2` with the old
    state in its `where`.
  - **RACE2-count-then-insert** — a count (`Repo.aggregate(_, :count)`, a
    `count_*` call, a `*_cap?`/`*_limit*` check, a `Gamend.Limits` read)
    and an insert in one function. Concurrent inserts all pass the count. Take
    the lock of the entity the cap belongs to around both.
  - **RACE3-cached-gate** — a struct from a cached read (`Accounts.get_user/1`)
    decides a branch that writes. The cache can be a TTL old. Decide from the
    database inside the transaction (`Gamend.Cache.cached/3` reads the source
    there), or from the row the write answers.
  """

  @type violation :: %{
          rule: String.t(),
          file: String.t(),
          line: pos_integer(),
          message: String.t()
        }

  @rules [
    {"RACE1-transition-by-struct",
     "A status/state/seat column is written by Repo.update on a struct read earlier"},
    {"RACE2-count-then-insert", "A count or cap check and an insert, with no lock around both"},
    {"RACE3-cached-gate", "A cached read decides a branch that writes"}
  ]

  @marker "race-safe:"

  # `{module alias, function}`: the last segment of the alias, so `Lock`
  # covers `Gamend.Lock` aliased or written out. A host adds its own lock
  # helpers in `config :gamend_core, Gamend.RaceLint, guards: [...]`.
  @guards [
    {:Repo, :compare_and_set},
    {:Repo, :lock_rows},
    {nil, :compare_and_set},
    {nil, :lock_rows},
    {:Lock, :serialize},
    {:Lock, :exclusive},
    {:Local, :trans},
    {:AdvisoryLock, :lock}
  ]
  @updates ~w(update update!)a
  @inserts ~w(insert insert! insert_all insert_or_update insert_or_update!)a
  @writes @updates ++ @inserts ++ ~w(update_all delete delete! delete_all)a

  # Columns whose value is a state a rule is about: which lobby a player sits
  # in, whether a request is still pending, whether something was paid.
  @transition_fields ~w(status state lobby_id party_id group_id match_id resolved_at
                        claimed_at accepted_at rejected_at revoked_at cancelled_at
                        fulfilled_at finished_at completed_at)a

  @cached_reads [{:Accounts, :get_user}]

  # Scanned in the engine and in every host built on it: core and web, and a
  # host's own `lib/` and `modules/` (core/web under deps there).
  @roots [
    "apps/gamend_core/lib",
    "apps/gamend_web/lib",
    "deps/gamend_core/apps/gamend_core/lib",
    "deps/gamend_web/apps/gamend_web/lib",
    "lib",
    "modules"
  ]

  @doc "The checks, as `{id, description}`."
  @spec rules() :: [{String.t(), String.t()}]
  def rules, do: @rules

  @doc "Every violation under the scan roots, ordered by rule then file."
  @spec violations() :: [violation()]
  def violations do
    guards = @guards ++ extra_guards()

    @roots
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(&ex_files/1)
    |> Enum.uniq()
    |> Enum.flat_map(&violations_in(File.read!(&1), &1, guards))
    |> Enum.sort_by(&{&1.rule, &1.file, &1.line})
  end

  defp extra_guards do
    :gamend_core |> Application.get_env(__MODULE__, []) |> Keyword.get(:guards, [])
  end

  # A root may itself sit under deps/ (core/web in a host), but anything
  # nested below it, a plugin's own deps or build, is third-party code.
  defp ex_files(root) do
    for path <- Path.wildcard(Path.join(root, "**/*.ex")),
        rest = String.trim_leading(path, root),
        not String.contains?(rest, "/deps/"),
        not String.contains?(rest, "/_build/"),
        do: path
  end

  @doc """
  The violations in one file's source. `guards` are the `{alias, function}`
  calls that make a function safe (the built-in ones by default).
  """
  @spec violations_in(String.t(), String.t(), [{atom() | nil, atom()}]) :: [violation()]
  def violations_in(source, path, guards \\ @guards) do
    case Code.string_to_quoted(source, token_metadata: true, columns: false) do
      {:ok, ast} ->
        lines = String.split(source, "\n")
        functions = functions(ast)
        guards = local_guards(functions, guards)

        for {name, _fun, first, last, body} <- functions,
            not marked?(lines, first, last),
            {rule, message} <- check(body, guards) do
          %{rule: rule, file: path, line: first, message: "#{name}: #{message}"}
        end

      {:error, _} ->
        []
    end
  end

  # The file's own functions that call a guard, directly or through another
  # of them, added as `{nil, name}` guards until no more are found.
  defp local_guards(functions, guards) do
    found =
      for {_name, fun, _first, _last, body} <- functions,
          is_atom(fun),
          {nil, fun} not in guards,
          guarded?(calls(body), guards),
          uniq: true,
          do: {nil, fun}

    if found == [], do: guards, else: local_guards(functions, guards ++ found)
  end

  defp marked?(lines, first, last) do
    lines
    |> Enum.slice((first - 1)..(last - 1)//1)
    |> Enum.any?(&String.contains?(&1, @marker))
  end

  defp functions(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [head, [{_do, body} | _] = _blocks]} = node, acc
        when kind in [:def, :defp] ->
          first = meta[:line]
          last = get_in(meta, [:end, :line]) || first
          {node, [{name_of(head), fun_of(head), first, last, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp fun_of({:when, _, [head | _]}), do: fun_of(head)
  defp fun_of({name, _, args}) when is_atom(name) and is_list(args), do: name
  defp fun_of({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: name
  defp fun_of(_head), do: nil

  defp name_of({:when, _, [head | _]}), do: name_of(head)
  defp name_of({name, _, args}) when is_atom(name), do: "#{name}/#{length(List.wrap(args))}"
  defp name_of(_head), do: "?"

  defp check(body, guards) do
    calls = calls(body)

    if guarded?(calls, guards) do
      []
    else
      Enum.reject(
        [
          transition_by_struct(body, calls),
          count_then_insert(calls),
          cached_gate(body, calls)
        ],
        &is_nil/1
      )
    end
  end

  defp guarded?(calls, guards),
    do: Enum.any?(calls, fn {mod, fun, _args} -> {mod, fun} in guards end)

  defp repo_calls(calls, funs),
    do: for({:Repo, fun, _args} <- calls, fun in funs, do: fun)

  # ── RACE1 ───────────────────────────────────────────────────────────────

  defp transition_by_struct(body, calls) do
    if repo_calls(calls, @updates) != [] and sets_transition_field?(body) do
      {"RACE1-transition-by-struct",
       "writes a state column with Repo.update on a struct read earlier; two callers can " <>
         "both have read the old state. Use Repo.compare_and_set/2 with it in the where."}
    end
  end

  defp sets_transition_field?(body) do
    {_ast, found?} =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, [:Ecto, :Changeset]}, :change]}, _, args} = node, acc ->
          {node, acc or Enum.any?(args, &transition_attrs?/1)}

        {:change, _, args} = node, acc when is_list(args) ->
          {node, acc or Enum.any?(args, &transition_attrs?/1)}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp transition_attrs?({:%{}, _, pairs}), do: transition_attrs?(pairs)

  defp transition_attrs?(pairs) when is_list(pairs) do
    Enum.any?(pairs, fn
      {key, _value} -> key in @transition_fields
      _other -> false
    end)
  end

  defp transition_attrs?(_arg), do: false

  # ── RACE2 ───────────────────────────────────────────────────────────────

  defp count_then_insert(calls) do
    if repo_calls(calls, @inserts) != [] and Enum.any?(calls, &counting?/1) do
      {"RACE2-count-then-insert",
       "counts (or checks a cap) and inserts with no lock around both; concurrent " <>
         "inserts all pass the count. Lock the entity the cap belongs to."}
    end
  end

  defp counting?({:Repo, :aggregate, args}), do: :count in args
  defp counting?({:Limits, _fun, _args}), do: true

  defp counting?({_mod, fun, _args}) do
    name = Atom.to_string(fun)

    String.starts_with?(name, "count_") or
      (String.ends_with?(name, "?") and (name =~ "cap" or name =~ "limit"))
  end

  # ── RACE3 ───────────────────────────────────────────────────────────────

  defp cached_gate(body, calls) do
    vars = cached_vars(body)

    if vars != [] and repo_calls(calls, @writes) != [] and decides_on?(body, vars) do
      {"RACE3-cached-gate",
       "a cached read (#{Enum.map_join(@cached_reads, ", ", fn {m, f} -> "#{m}.#{f}" end)}) " <>
         "decides a branch that writes; the cache can be a TTL old. Decide from the " <>
         "database in the transaction, or from the row the write answers."}
    end
  end

  defp cached_vars(body) do
    {_ast, vars} =
      Macro.prewalk(body, [], fn
        {:=, _, [{var, _, ctx}, rhs]} = node, acc when is_atom(var) and is_atom(ctx) ->
          if cached_read?(rhs), do: {node, [var | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    vars
  end

  defp cached_read?({{:., _, [{:__aliases__, _, parts}, fun]}, _, _args}),
    do: {List.last(parts), fun} in @cached_reads

  defp cached_read?({:|>, _, [_lhs, rhs]}), do: cached_read?(rhs)
  defp cached_read?(_expr), do: false

  # A field of the cached struct read in the condition of an if/unless/cond
  # clause, a case subject or a with clause.
  defp decides_on?(body, vars) do
    {_ast, found?} =
      Macro.prewalk(body, false, fn
        {kind, _, [condition | _]} = node, acc when kind in [:if, :unless, :case] ->
          {node, acc or reads_field?(condition, vars)}

        {:cond, _, [[do: clauses]]} = node, acc ->
          {node, acc or Enum.any?(clauses, fn {:->, _, [[c], _]} -> reads_field?(c, vars) end)}

        {:with, _, clauses} = node, acc ->
          matches = for {:<-, _, [_pattern, rhs]} <- clauses, do: rhs
          {node, acc or Enum.any?(matches, &reads_field?(&1, vars))}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp reads_field?(expr, vars) do
    {_ast, found?} =
      Macro.prewalk(expr, false, fn
        {{:., _, [{var, _, ctx}, field]}, _, []} = node, acc
        when is_atom(var) and is_atom(ctx) and is_atom(field) ->
          {node, acc or var in vars}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  # ── calls ───────────────────────────────────────────────────────────────

  defp calls(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, parts}, fun]}, _, args} = node, acc
        when is_atom(fun) and is_list(args) ->
          {node, [{List.last(parts), fun, args} | acc]}

        {fun, _, args} = node, acc when is_atom(fun) and is_list(args) ->
          {node, [{nil, fun, args} | acc]}

        node, acc ->
          {node, acc}
      end)

    found
  end
end
