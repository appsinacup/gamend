defmodule Gamend.LiteralLint do
  @moduledoc """
  Finds the strings that are really names: a status, an action, a kind, typed
  out wherever it is used. `mix gamend.literal.lint` runs it.

  `"creat"` compiles, and the module that reads it simply never matches. A
  name that one module writes and another reads belongs to a module that owns
  it, and everyone else asks that module (CONTRIBUTING.md, "Named strings").

  A string counts when it is shaped like a name (`"failed"`, `"move_in"`,
  `"gamend.db"`, no spaces) and stands in code, and it is reported when it
  stands in two or more modules, or five or more times in one. These do not
  count, because a name for them would say less than they do:

    * the value of a module attribute, or a function that is nothing but its
      value: `@failed "failed"` and `defmacro failed, do: "failed"` are the cure
    * a key: `%{"id" => id}`, `params["id"]`, `Map.get(params, "id")`, `get_in/2`.
      Keys are the shape of a document, not a closed set of values
    * text: gettext, `Logger`, `raise`, `IO`, `Mix`, `System`, and any sigil
      other than a string `~w`, so a HEEx template is not read
    * a LiveView event's name in `handle_event/3`, and HTTP header names
    * an API error's code in `reply_error/3`, which has to be a literal:
      `mix gamend.api.lint` (R18) holds it to `GamendWeb.ErrorStatus`
    * a CSS class of the shared vocabulary (`"badge-error"`), and `"true"`

  It is a heuristic, and says so. A use it is wrong about is marked with the
  reason, on its line or the line above:

      # literal-ok: Stripe's event name
      "invoice.paid" -> paid(event)

  What was already there when the check arrived is counted in
  `.literal-lint-baseline`. A string there may appear that many times and no
  more, so the count only goes down.
  """

  @type occurrence :: %{
          literal: String.t(),
          file: String.t(),
          line: pos_integer() | nil,
          module: String.t() | nil
        }

  @type offender :: %{
          literal: String.t(),
          count: pos_integer(),
          modules: pos_integer(),
          occurrences: [occurrence()]
        }

  @type baseline :: %{optional(String.t()) => non_neg_integer()}

  @baseline_file ".literal-lint-baseline"
  @marker "literal-ok:"

  @min_modules 2
  @min_uses_in_one_module 5

  # The engine and every host: `lib/`, an umbrella's apps, and plugins.
  @roots ["lib", "apps/*/lib", "sdk_tools/lib", "modules/*/*/lib"]

  @separators ~c".:-"
  @css_prefixes ~w(alert- badge- bg- border- btn- font- hero- link- loading- text- tooltip-)
  @not_names ~w(true false nil null)

  @definitions ~w(def defp defmacro defmacrop)a
  @map_keyed ~w(delete fetch fetch! get has_key? pop put put_new replace replace! update update!)a

  # Text, a command line, or a path into a document: not a value of ours.
  @silent_modules ~w(Logger Gettext IO Mix System)a
  @silent_calls ~w(gettext dgettext dpgettext dngettext ngettext pgettext raise reraise
                   reply_error get_in put_in update_in pop_in
                   get_req_header get_resp_header put_req_header put_resp_header
                   delete_req_header delete_resp_header)a

  @doc "Where the counts of what was already there are kept."
  @spec baseline_file() :: String.t()
  def baseline_file, do: @baseline_file

  @doc "Every string under the scan roots that should be named, most used first."
  @spec offenders() :: [offender()]
  def offenders do
    @roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.reject(&third_party?/1)
    |> Enum.uniq()
    |> Enum.flat_map(&occurrences_in(File.read!(&1), &1))
    |> offenders()
  end

  defp third_party?(path) do
    String.contains?(path, ["/deps/", "/_build/", "/node_modules/"]) or
      String.ends_with?(path, ".pb.ex")
  end

  @doc "Groups occurrences into the strings that should be named, most used first."
  @spec offenders([occurrence()]) :: [offender()]
  def offenders(occurrences) when is_list(occurrences) do
    occurrences
    |> Enum.group_by(& &1.literal)
    |> Enum.map(fn {literal, found} ->
      %{
        literal: literal,
        count: length(found),
        modules: found |> Enum.uniq_by(& &1.module) |> length(),
        occurrences: Enum.sort_by(found, &{&1.file, &1.line})
      }
    end)
    |> Enum.filter(&offends?/1)
    |> Enum.sort_by(&{-&1.count, &1.literal})
  end

  defp offends?(%{modules: modules, count: count}) do
    modules >= @min_modules or count >= @min_uses_in_one_module
  end

  @doc "The offenders beyond what the baseline allows."
  @spec new_offenders([offender()], baseline()) :: [offender()]
  def new_offenders(offenders, baseline) do
    Enum.filter(offenders, &(&1.count > Map.get(baseline, &1.literal, 0)))
  end

  @doc "The baseline in the working directory, empty if there is none."
  @spec read_baseline(String.t()) :: baseline()
  def read_baseline(path \\ @baseline_file) do
    case File.read(path) do
      {:ok, text} -> parse_baseline(text)
      {:error, _reason} -> %{}
    end
  end

  @doc "Reads a baseline's text: `<count> <string>`, a line each, `#` for a comment."
  @spec parse_baseline(String.t()) :: baseline()
  def parse_baseline(text) do
    for line <- String.split(text, "\n"),
        [count, literal] <- [String.split(line, " ", parts: 2)],
        match?({_, ""}, Integer.parse(count)),
        into: %{},
        do: {literal, String.to_integer(count)}
  end

  @doc "The text of a baseline holding these offenders."
  @spec format_baseline([offender()]) :: String.t()
  def format_baseline(offenders) do
    entries = offenders |> Enum.sort_by(& &1.literal) |> Enum.map(&"#{&1.count} #{&1.literal}\n")

    IO.iodata_to_binary([
      "# Strings typed out in several modules, and how many times each may appear.\n",
      "# Give one a name and its count falls; nothing here may grow.\n",
      "# Written by `mix gamend.literal.lint --update-baseline`.\n"
      | entries
    ])
  end

  @doc "The named-looking strings in one file's source."
  @spec occurrences_in(String.t(), String.t()) :: [occurrence()]
  def occurrences_in(source, path) do
    encoder = fn literal, meta -> {:ok, {:__block__, meta, [literal]}} end

    case Code.string_to_quoted(source, literal_encoder: encoder) do
      {:ok, ast} ->
        marked = marked_lines(source)

        ast
        |> walk(nil, [])
        |> Enum.reject(fn {_literal, line, _module} -> MapSet.member?(marked, line) end)
        |> Enum.map(fn {literal, line, module} ->
          %{literal: literal, file: path, line: line, module: module}
        end)

      {:error, _reason} ->
        []
    end
  end

  defp marked_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {text, _line} -> String.contains?(text, "# " <> @marker) end)
    |> Enum.map(fn {text, line} ->
      if text |> String.trim_leading() |> String.starts_with?("#"), do: line + 1, else: line
    end)
    |> MapSet.new()
  end

  # An attribute holds prose or a definition, and a definition is the cure.
  defp walk({:@, _, _}, _module, acc), do: acc

  # So does a function that is nothing but its value.
  defp walk({kind, _, [{_name, _, args}, [{_do, {:__block__, _, [literal]}}]]}, _module, acc)
       when kind in @definitions and args in [nil, []] and is_binary(literal),
       do: acc

  defp walk({:__block__, meta, [literal]}, module, acc) when is_binary(literal) do
    if name?(literal), do: [{literal, meta[:line], module} | acc], else: acc
  end

  defp walk({:defmodule, _, [name, body]}, parent, acc) do
    walk(body, module_name(name, parent), acc)
  end

  defp walk({:%{}, _, pairs}, module, acc), do: walk_pairs(pairs, module, acc)

  defp walk({{:., _, [Access, :get]}, _, [map, _key]}, module, acc), do: walk(map, module, acc)

  defp walk({{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, args}, module, acc)
       when fun in @map_keyed do
    walk(without_key(args), module, acc)
  end

  defp walk({{:., _, [{:__aliases__, _, [head | _]}, _]}, _, _}, _module, acc)
       when head in @silent_modules,
       do: acc

  defp walk({name, _, args}, _module, acc) when name in @silent_calls and is_list(args), do: acc

  defp walk({:handle_event, _, [_event | rest]}, module, acc), do: walk(rest, module, acc)

  defp walk({:sigil_w, meta, [{:<<>>, _, [words]}, []]}, module, acc) when is_binary(words) do
    for word <- String.split(words), name?(word), reduce: acc do
      acc -> [{word, meta[:line], module} | acc]
    end
  end

  defp walk({name, _, args}, module, acc) when is_atom(name) do
    if sigil?(name), do: acc, else: walk(args, module, acc)
  end

  defp walk({call, _, args}, module, acc), do: walk(args, module, walk(call, module, acc))
  defp walk({left, right}, module, acc), do: walk(right, module, walk(left, module, acc))

  defp walk(list, module, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk(&1, module, &2))
  end

  defp walk(_other, _module, acc), do: acc

  # A map's keys are skipped, in a literal and in an update alike.
  defp walk_pairs(pairs, module, acc) do
    Enum.reduce(pairs, acc, fn
      {:|, _, [map, updates]}, acc -> walk_pairs(updates, module, walk(map, module, acc))
      {_key, value}, acc -> walk(value, module, acc)
      other, acc -> walk(other, module, acc)
    end)
  end

  # `map |> Map.get("key")` has the key first, `Map.get(map, "key")` second.
  defp without_key([{:__block__, _, [key]} | rest]) when is_binary(key), do: rest
  defp without_key([map, _key | rest]), do: [map | rest]
  defp without_key(args), do: args

  defp sigil?(name), do: name |> Atom.to_string() |> String.starts_with?("sigil_")

  defp module_name(name, parent) do
    [parent, Macro.to_string(name)] |> Enum.reject(&is_nil/1) |> Enum.join(".")
  end

  defp name?(<<first, _, _::binary>> = literal) when first in ?a..?z do
    shaped?(literal) and :binary.last(literal) not in @separators and
      literal not in @not_names and not String.starts_with?(literal, @css_prefixes)
  end

  defp name?(_literal), do: false

  defp shaped?(<<char, rest::binary>>)
       when char in ?a..?z or char in ?0..?9 or char == ?_ or char in @separators,
       do: shaped?(rest)

  defp shaped?(<<>>), do: true
  defp shaped?(_literal), do: false
end
