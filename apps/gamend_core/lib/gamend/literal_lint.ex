defmodule Gamend.LiteralLint do
  @moduledoc """
  Finds the strings that are really names: a status, an action, a kind, typed
  out wherever it is used. `mix gamend.literal.lint` runs it.

  `"creat"` compiles, and the module that reads it simply never matches. A
  name that one module writes and another reads belongs to a module that owns
  it, and everyone else asks that module (CONTRIBUTING.md, "Named strings").

  A string counts when it is shaped like a name (`"failed"`, `"move_in"`,
  `"gamend.db"`, no spaces) and stands in code, and it is reported when it
  stands in two or more modules, or five or more times in one. In a template
  (`~H`, `.heex`) only a comparison counts: `@s == "failed"`.

  `@failed "failed"` and `defp failed, do: "failed"` name a string for their
  own module, which is fine, until a second module of the same context gives
  the same string the same name. Then the name has two homes, and needs an
  owner. Across contexts the same word is nearly always a different thing
  (`@page` in a schema, `@page` in a presence record).

  These do not count, because a name for them would say less than they do:

    * what an owner declares: `use Gamend.Names`, and a public function that
      is nothing but its value (`defmacro failed, do: "failed"`)
    * documentation attributes
    * a key: `%{"id" => id}`, `params["id"]`, `Map.get(params, "id")`, `Map.take/2`,
      `get_in/2`. Keys are the shape of a document, not a closed set of values
    * text: gettext, `Logger`, `raise`, `IO`, `Mix`, `System`, and any sigil
      other than a string `~w` or a template
    * a LiveView event's name in `handle_event/3`, and HTTP header names
    * an API error's code in `reply_error/3`, which has to be a literal:
      `mix gamend.api.lint` (R18) holds it to `GamendWeb.ErrorStatus`
    * a CSS class of the shared vocabulary (`"badge-error"`), and `"true"`

  It is a heuristic, and says so. A use it is wrong about is marked with the
  reason, on its line or the line above:

      # literal-ok: Stripe's event name
      "invoice.paid" -> paid(event)

      <%!-- literal-ok: the browser's value --%>
      <b :if={@kind == "submit"}>x</b>
  """

  @type occurrence :: %{
          literal: String.t(),
          file: String.t(),
          line: pos_integer() | nil,
          module: String.t() | nil,
          as: atom()
        }

  @type offender :: %{
          literal: String.t(),
          count: pos_integer(),
          modules: pos_integer(),
          occurrences: [occurrence()]
        }

  @markers ["# literal-ok:", "<%!-- literal-ok:"]
  @comment_openers ["#", "<%!--"]

  @min_modules 2
  @min_uses_in_one_module 5

  # The engine and every host: `lib/`, an umbrella's apps, and plugins.
  @roots ["lib", "apps/*/lib", "sdk_tools/lib", "modules/*/*/lib"]

  @separators ~c".:-"
  @css_prefixes ~w(alert- badge- bg- border- btn- font- hero- link- loading- text- tooltip-)
  @not_names ~w(true false nil null)

  @public_definitions ~w(def defmacro)a
  @private_definitions ~w(defp defmacrop)a
  @documentation ~w(moduledoc doc shortdoc typedoc deprecated)a
  @map_keyed ~w(delete fetch fetch! get has_key? pop put put_new replace replace! update update!)a
  @map_key_lists ~w(drop split take)a

  # Text, a command line, or a path into a document: not a value of ours.
  @silent_modules ~w(Logger Gettext IO Mix System)a
  @silent_calls ~w(gettext dgettext dpgettext dngettext ngettext pgettext
                   gettext_noop dgettext_noop dpgettext_noop dngettext_noop ngettext_noop
                   pgettext_noop raise reraise
                   reply_error get_in put_in update_in pop_in
                   get_req_header get_resp_header put_req_header put_resp_header
                   delete_req_header delete_resp_header)a

  @doc "Every string under the scan roots that should be named, most used first."
  @spec offenders() :: [offender()]
  def offenders do
    @roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.{ex,heex}")))
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
    |> without_local_names()
    |> Enum.group_by(& &1.literal)
    |> Enum.map(fn {literal, found} ->
      %{
        literal: literal,
        count: length(found),
        modules: module_count(found),
        occurrences: Enum.sort_by(found, &{&1.file, &1.line})
      }
    end)
    |> Enum.filter(&offends?/1)
    |> Enum.sort_by(&{-&1.count, &1.literal})
  end

  defp without_local_names(occurrences) do
    shared =
      occurrences
      |> Enum.filter(& &1.as)
      |> Enum.group_by(&local_name/1)
      |> Enum.filter(fn {_name, found} -> module_count(found) >= @min_modules end)
      |> MapSet.new(fn {name, _found} -> name end)

    Enum.filter(occurrences, &(is_nil(&1.as) or MapSet.member?(shared, local_name(&1))))
  end

  defp local_name(%{literal: literal, as: as, module: module}) do
    {literal, as, context(module)}
  end

  # `Gamend.Payments.Counters` and `Gamend.Payments` are one context.
  defp context(nil), do: nil
  defp context(module), do: module |> String.split(".") |> Enum.take(2)

  defp module_count(found), do: found |> Enum.uniq_by(& &1.module) |> length()

  defp offends?(%{modules: modules, count: count}) do
    modules >= @min_modules or count >= @min_uses_in_one_module
  end

  @doc "The named-looking strings in one file's source."
  @spec occurrences_in(String.t(), String.t()) :: [occurrence()]
  def occurrences_in(source, path) do
    marked = marked_lines(source)

    source
    |> found_in(path)
    |> Enum.reject(fn {_literal, line, _module, _as} -> MapSet.member?(marked, line) end)
    |> Enum.map(fn {literal, line, module, as} ->
      %{literal: literal, file: path, line: line, module: module, as: as}
    end)
  end

  defp found_in(source, path) do
    if String.ends_with?(path, ".heex") do
      compared(source, 1, path, [])
    else
      encoder = fn literal, meta -> {:ok, {:__block__, meta, [literal]}} end

      case Code.string_to_quoted(source, literal_encoder: encoder) do
        {:ok, ast} -> walk(ast, nil, [])
        {:error, _reason} -> []
      end
    end
  end

  defp marked_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {text, _line} -> String.contains?(text, @markers) end)
    |> Enum.map(fn {text, line} ->
      if text |> String.trim_leading() |> String.starts_with?(@comment_openers),
        do: line + 1,
        else: line
    end)
    |> MapSet.new()
  end

  # A template is markup: only a comparison in it reads a value of ours.
  defp compared(template, first_line, module, acc) do
    for {text, line} <- template |> String.split("\n") |> Enum.with_index(first_line),
        [literal] <- Regex.scan(compared_string(), text, capture: :all_but_first),
        name?(literal),
        reduce: acc do
      acc -> [{literal, line, module, nil} | acc]
    end
  end

  # A function, not an attribute: a compiled regex cannot be stored in one.
  defp compared_string, do: ~r/(?|(?:==|!=)\s*"([^"\s]+)"|"([^"\s]+)"\s*(?:==|!=))/

  defp walk({:@, _, [{name, _, [{:__block__, meta, [value]}]}]}, module, acc)
       when is_binary(value) and name not in @documentation do
    if name?(value), do: [{value, meta[:line], module, name} | acc], else: acc
  end

  defp walk({:@, _, _}, _module, acc), do: acc

  # An owner's declaration of its names.
  defp walk({:use, _, [{:__aliases__, _, [:Gamend, :Names]} | _]}, _module, acc), do: acc

  defp walk({kind, _, [{_name, _, args}, [{_do, {:__block__, _, [literal]}}]]}, _module, acc)
       when kind in @public_definitions and args in [nil, []] and is_binary(literal),
       do: acc

  defp walk({kind, _, [{name, _, args}, [{_do, {:__block__, meta, [literal]}}]]}, module, acc)
       when kind in @private_definitions and args in [nil, []] and is_binary(literal) do
    if name?(literal), do: [{literal, meta[:line], module, name} | acc], else: acc
  end

  defp walk({:__block__, meta, [literal]}, module, acc) when is_binary(literal) do
    if name?(literal), do: [{literal, meta[:line], module, nil} | acc], else: acc
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

  # Whether piped or not, the list of keys comes last.
  defp walk({{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, args}, module, acc)
       when fun in @map_key_lists do
    walk(Enum.drop(args, -1), module, acc)
  end

  defp walk({{:., _, [{:__aliases__, _, [head | _]}, _]}, _, _}, _module, acc)
       when head in @silent_modules,
       do: acc

  defp walk({name, _, args}, _module, acc) when name in @silent_calls and is_list(args), do: acc

  defp walk({:handle_event, _, [_event | rest]}, module, acc), do: walk(rest, module, acc)

  defp walk({:sigil_w, meta, [{:<<>>, _, [words]}, []]}, module, acc) when is_binary(words) do
    for word <- String.split(words), name?(word), reduce: acc do
      acc -> [{word, meta[:line], module, nil} | acc]
    end
  end

  defp walk({:sigil_H, meta, [{:<<>>, _, [template]}, []]}, module, acc)
       when is_binary(template) do
    # A heredoc's text starts on the line after its delimiter.
    first_line = if meta[:delimiter] == ~S("""), do: meta[:line] + 1, else: meta[:line]
    compared(template, first_line, module, acc)
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
