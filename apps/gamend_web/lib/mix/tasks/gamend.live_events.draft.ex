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

  A draft is a guess to review, never the answer:

    * a key every clause of the event matches is required, one only some
      match is `{:optional, ...}`;
    * a literal string value, or a variable a guard holds to a list of
      strings, is `:string`; `is_integer/1` is `:integer`, `is_boolean/1`
      `:boolean`; a nested `%{...}` pattern is its own keys;
    * a key named `id`, `*_id` or `*-id` is `:uuid`, the engine's ids;
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

    with true <- String.contains?(source, "def handle_event("),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true) do
      declared =
        ~r/^\s*event\(\s*"([^"]+)"/m
        |> Regex.scan(source, capture: :all_but_first)
        |> List.flatten()

      events = ast |> clauses() |> undeclared(declared)

      for {_line, name, declaration} <- events,
          do: Mix.shell().info("#{file}: event(#{inspect(name)}#{render_keys(declaration)})")

      if apply? == true and events != [], do: File.write!(file, insert(source, events))
      length(events)
    else
      _ -> 0
    end
  end

  # Every `def handle_event(name, pattern, socket)` with a literal name: its
  # line, name, pattern and guard.
  defp clauses(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:def, meta, [{:when, _, [{:handle_event, _, [name, pattern, _socket]}, guard]} | _]} =
            node,
        acc ->
          {node, [{meta[:line], literal(name), pattern, guard} | acc]}

        {:def, meta, [{:handle_event, _, [name, pattern, _socket]} | _]} = node, acc ->
          {node, [{meta[:line], literal(name), pattern, nil} | acc]}

        node, acc ->
          {node, acc}
      end)

    found |> Enum.reverse() |> Enum.reject(&is_nil(elem(&1, 1)))
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

  defp type(key, value, guard) do
    var = var(value)

    cond do
      match?({:%{}, _, _}, value) -> keys(value, guard)
      id_key?(key) -> :uuid
      is_binary(value) -> :string
      var && guarded?(guard, var, :is_integer) -> :integer
      var && guarded?(guard, var, :is_boolean) -> :boolean
      var && guarded?(guard, var, :is_list) -> {:list, :string}
      var && String.ends_with?(Atom.to_string(var), "params") -> {:map_of, :string}
      true -> :string
    end
  end

  defp id_key?(key),
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
