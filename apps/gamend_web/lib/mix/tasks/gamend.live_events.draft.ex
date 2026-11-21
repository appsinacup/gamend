defmodule Mix.Tasks.Gamend.LiveEvents.Draft do
  @shortdoc "Drafts an event/2 declaration above every undeclared LiveView handler"

  @moduledoc """
  Writes `event("name", key: type)` above each `handle_event/3` that no
  declaration names yet (`GamendWeb.LiveEvents`), drafted from the handler's
  own pattern, so a project adopting the check starts from its code, not a
  blank page:

      mix gamend.live_events.draft              # every file under lib/, dry run
      mix gamend.live_events.draft --apply      # write them
      mix gamend.live_events.draft lib/my_app_web/live/page_live.ex --apply

  Besides `handle_event/3`, it reads the hook a module names
  (`use GamendWeb.LiveEvents, hook: :on_event`) and the functions it hands
  events to (`@live_event_handlers [run: 3]`).

  A draft is a guess to review, never the answer:

    * a key every clause of the event matches is required, one only some
      match is `{:optional, ...}`;
    * a literal string value is `:string`, a literal list `{:list, :string}`
      (a form's `_target`); a guard `is_integer/1` is
      `:integer`, `is_boolean/1` `:boolean`, `x in ["a", "b"]`
      `{:in, ["a", "b"]}`; a nested `%{...}` pattern is its own keys;
    * a key named `id`, `*_id` or `*-id` that no guard types is `:id` (a
      string or an integer); one that names a row is `:uuid`, which the
      wrong-types tests say where it is missing (a query raising on "nope");
    * `is_map/1` is `{:map_of, :string}`;
    * a variable named `*params` (a form's fields) is `{:map_of, :string}`;
      a form over a changeset reads better as `{:schema, Module}`.

  `mix gamend.contract.lint` then fails on a handled event left undeclared,
  and the project's wrong-types tests (`GamendWeb.Testing.WrongTypes`) on a
  declaration that refuses what its page sends.
  """

  use Mix.Task

  @impl true
  def run(argv) do
    {opts, files, _} = OptionParser.parse(argv, strict: [apply: :boolean])
    files = if files == [], do: Path.wildcard("lib/**/*.ex"), else: files

    drafted =
      for file <- files, (count = draft(file, opts[:apply])) > 0, reduce: 0 do
        acc -> acc + count
      end

    Mix.shell().info(
      "#{drafted} event(s) #{if opts[:apply], do: "declared", else: "to declare (dry run)"}"
    )
  end

  defp draft(file, apply?) do
    source = File.read!(file)

    with true <- String.contains?(source, "handle_event("),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true) do
      declared =
        ~r/^\s*event\(\s*"([^"]+)"/m
        |> Regex.scan(source, capture: :all_but_first)
        |> List.flatten()

      events = ast |> clauses(handlers(ast)) |> undeclared(declared)

      for {_line, name, declaration} <- events,
          do: Mix.shell().info("#{file}: event(#{inspect(name)}#{render_keys(declaration)})")

      if apply? == true and events != [], do: File.write!(file, insert(source, events))
      length(events)
    else
      _ -> 0
    end
  end

  # The functions that take events: `handle_event/3`, a named hook, and the
  # `@live_event_handlers` a module lists.
  defp handlers(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [{:handle_event, 3}], fn
        {:use, _, [{:__aliases__, _, [:GamendWeb, :LiveEvents]}, opts]} = node, acc
        when is_list(opts) ->
          {node, acc ++ hook(opts[:hook])}

        {:@, _, [{:live_event_handlers, _, [list]}]} = node, acc when is_list(list) ->
          {node, acc ++ list}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp hook(nil), do: []
  defp hook({:{}, _, [name, arity]}), do: [{name, arity}]
  defp hook({name, arity}), do: [{name, arity}]
  defp hook(name) when is_atom(name), do: [{name, 3}]

  # Every clause of those with a literal event name: its line, name, pattern
  # and guard.
  defp clauses(ast, handlers) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{:when, _, [{fun, _, [name, pattern | _] = args}, guard]} | _]} = node, acc
        when kind in [:def, :defp] and is_atom(fun) and is_list(args) ->
          {node, clause(handlers, fun, args, meta, name, pattern, guard, acc)}

        {kind, meta, [{fun, _, [name, pattern | _] = args} | _]} = node, acc
        when kind in [:def, :defp] and is_atom(fun) and is_list(args) ->
          {node, clause(handlers, fun, args, meta, name, pattern, nil, acc)}

        node, acc ->
          {node, acc}
      end)

    found |> Enum.reverse() |> Enum.reject(&is_nil(elem(&1, 1)))
  end

  defp clause(handlers, fun, args, meta, name, pattern, guard, acc) do
    if {fun, length(args)} in handlers,
      do: [{meta[:line], literal(name), pattern, guard} | acc],
      else: acc
  end

  defp literal(name) when is_binary(name), do: name
  defp literal({:=, _, [left, right]}), do: literal(left) || literal(right)
  defp literal(_), do: nil

  defp undeclared(clauses, declared) do
    clauses
    |> Enum.reject(fn {_line, name, _p, _g} -> name in declared end)
    |> Enum.group_by(&elem(&1, 1))
    |> Enum.map(fn {name, of_event} ->
      line = of_event |> Enum.map(&elem(&1, 0)) |> Enum.min()

      {line, name,
       merge(Enum.map(of_event, fn {_l, _n, pattern, guard} -> keys(pattern, guard) end))}
    end)
    |> Enum.sort()
  end

  # The keys a pattern matches, each with its type.
  defp keys({:=, _, [left, right]}, guard), do: keys(left, guard) ++ keys(right, guard)

  defp keys({:%{}, _, pairs}, guard),
    do: for({key, value} <- pairs, is_binary(key), do: {key, type(key, value, guard)})

  defp keys(_pattern, _guard), do: []

  # A guard says more than a name, so it is read first.
  defp type(key, value, guard) do
    var = var(value)

    cond do
      match?({:%{}, _, _}, value) -> keys(value, guard)
      is_binary(value) -> :string
      # A literal list: a form's `_target`, `["q"]`.
      is_list(value) -> {:list, :string}
      var && guarded?(guard, var, :is_integer) -> :integer
      var && guarded?(guard, var, :is_boolean) -> :boolean
      var && guarded?(guard, var, :is_list) -> {:list, :string}
      var && guarded?(guard, var, :is_map) -> {:map_of, :string}
      var && in_list(guard, var) -> {:in, in_list(guard, var)}
      id_key?(key) -> :id
      var && String.ends_with?(Atom.to_string(var), "params") -> {:map_of, :string}
      true -> :string
    end
  end

  # The literal strings a `var in [...]` guard holds it to, or nil.
  defp in_list(nil, _var), do: nil

  defp in_list(guard, var) do
    {_ast, found} =
      Macro.prewalk(guard, nil, fn
        {:in, _, [{^var, _, _}, values]} = node, nil when is_list(values) ->
          {node, if(Enum.all?(values, &is_binary/1), do: values)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp id_key?(key),
    # literal-ok: the engine's id key, by its name in a pattern
    do: key == "id" or String.ends_with?(key, "_id") or String.ends_with?(key, "-id")

  defp var({:=, _, [left, right]}), do: var(left) || var(right)
  defp var({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var(_), do: nil

  defp guarded?(nil, _var, _fun), do: false

  defp guarded?(guard, var, fun) do
    {_ast, found} =
      Macro.prewalk(guard, false, fn
        {^fun, _, [{^var, _, _}]} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # A key every clause matches is required; one only some do, optional.
  defp merge(per_clause) do
    names =
      per_clause |> Enum.flat_map(fn clause -> Enum.map(clause, &elem(&1, 0)) end) |> Enum.uniq()

    for name <- names do
      types = for clause <- per_clause, {^name, type} <- clause, uniq: true, do: type
      type = if length(types) == 1, do: hd(types), else: :string
      everywhere? = Enum.all?(per_clause, &List.keymember?(&1, name, 0))
      {name, if(everywhere?, do: type, else: {:optional, type})}
    end
  end

  defp render_keys([]), do: ""
  defp render_keys(declaration), do: ", " <> render(declaration)

  defp render(declaration) do
    Enum.map_join(declaration, ", ", fn {key, type} ->
      "#{render_key(key)} #{render_type(type)}"
    end)
  end

  defp render_key(key) do
    if Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, key), do: "#{key}:", else: ~s("#{key}":)
  end

  defp render_type({:optional, type}), do: "{:optional, #{render_type(type)}}"
  defp render_type({:list, type}), do: "{:list, #{render_type(type)}}"
  defp render_type({:in, values}), do: "{:in, #{inspect(values)}}"
  defp render_type({:map_of, type}), do: "{:map_of, #{render_type(type)}}"
  defp render_type(keys) when is_list(keys), do: "[" <> render(keys) <> "]"
  defp render_type(type) when is_atom(type), do: inspect(type)

  # Each declaration on its own line above the event's first clause, and
  # above the `@impl`, `@doc` and comment lines that lead into it.
  defp insert(source, events) do
    lines = String.split(source, "\n")

    at =
      Map.new(events, fn {line, name, declaration} ->
        index = line - 1
        start = lead_in(lines, index)
        indent = Regex.run(~r/^\s*/, Enum.at(lines, index)) |> hd()
        {start, indent <> ~s|event("#{name}"#{render_keys(declaration)})| <> "\n"}
      end)

    lines
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, index} -> (at[index] || "") <> line end)
  end

  defp lead_in(lines, index) do
    Enum.reduce_while((index - 1)..0//-1, index, fn i, start ->
      text = String.trim(Enum.at(lines, i))

      if String.starts_with?(text, ["@impl", "@doc", "@spec", "#"]),
        do: {:cont, i},
        else: {:halt, start}
    end)
  end
end
