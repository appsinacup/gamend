defmodule Gamend.Hooks.PluginBuilder.Project do
  @moduledoc """
  What a plugin's `mix.exs` declares, read without evaluating it.

  The in-process build (`Gamend.Hooks.PluginBuilder.InProcess`) runs inside
  the server, so the project file is parsed with `Code.string_to_quoted/2` and
  only literal values are taken from it: `app`, `version`, `description` and
  `elixirc_paths` from `project/0`; `extra_applications`, `applications`,
  `env` and `mod` from `application/0`; and the name and options of each
  entry in `deps`.

  "Literal" includes what a mix.exs usually spells indirectly: a module
  attribute (`version: @version`), a local function returning a literal
  (`deps: deps()`, `elixirc_paths: elixirc_paths(Mix.env())`, resolved as
  `:prod`), and `System.get_env("X") || @version`, which reads the right-hand
  side. Anything else is left at its fallback and named in `warnings`:
  app = the directory name, version `"0.0.0"`, elixirc_paths `["lib"]`.
  """

  @type dep :: %{
          name: atom(),
          runtime?: boolean(),
          optional?: boolean(),
          prod?: boolean()
        }

  @type t :: %__MODULE__{
          app: atom(),
          version: String.t(),
          description: String.t() | nil,
          elixirc_paths: [String.t()],
          extra_applications: [atom()],
          applications: [atom()] | nil,
          env: keyword(),
          hooks_module: module() | nil,
          mod: {module(), term()} | nil,
          deps: [dep()],
          warnings: [String.t()]
        }

  defstruct app: nil,
            version: "0.0.0",
            description: nil,
            elixirc_paths: ["lib"],
            extra_applications: [],
            applications: nil,
            env: [],
            hooks_module: nil,
            mod: nil,
            deps: [],
            warnings: []

  # How deep `deps()` -> `shared_dep(...)` -> ... may nest before giving up.
  @max_depth 8

  @doc """
  Reads `<plugin_dir>/mix.exs`. The app name falls back to the directory's
  basename.
  """
  @spec read(Path.t()) :: {:ok, t()} | {:error, String.t()}
  def read(plugin_dir) do
    path = Path.join(plugin_dir, "mix.exs")
    fallback_app = plugin_dir |> Path.basename() |> String.to_atom()

    with {:ok, source} <- read_file(path),
         {:ok, ast} <- parse(source, path),
         {:ok, body} <- module_body(ast) do
      {:ok, from_body(body, fallback_app)}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, "cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp parse(source, path) do
    case Code.string_to_quoted(source, file: path, emit_warnings: false) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, {meta, message, token}} ->
        {:error, "#{path}:#{meta[:line]}: #{format_parse_message(message)}#{token}"}
    end
  end

  defp format_parse_message({prefix, suffix}), do: "#{prefix}#{suffix}"
  defp format_parse_message(message), do: to_string(message)

  defp module_body({:defmodule, _, [_alias, [do: body]]}), do: {:ok, block(body)}

  defp module_body({:__block__, _, exprs}) do
    Enum.find_value(exprs, {:error, "mix.exs defines no module"}, fn
      {:defmodule, _, _} = mod -> module_body(mod)
      _ -> nil
    end)
  end

  defp module_body(_ast), do: {:error, "mix.exs defines no module"}

  defp block({:__block__, _, exprs}), do: exprs
  defp block(expr), do: [expr]

  defp from_body(exprs, fallback_app) do
    ctx = %{
      attrs: collect_attributes(exprs),
      defs: collect_defs(exprs),
      depth: 0
    }

    project = keyword_ast(call_local(:project, [], ctx), ctx)
    application = keyword_ast(call_local(:application, [], ctx), ctx)

    %__MODULE__{app: fallback_app}
    |> read_project(project, ctx)
    |> read_application(application, ctx)
    # Collected newest first.
    |> Map.update!(:warnings, &Enum.reverse/1)
    |> Map.update!(:env, &Enum.reverse/1)
    |> Map.update!(:deps, &Enum.reverse/1)
  end

  defp read_project(acc, nil, _ctx),
    do: warn(acc, "project/0 is not a literal keyword list; using defaults")

  defp read_project(acc, kw, ctx) do
    acc
    |> take(kw, :app, ctx, &app_name?/1, &%{&1 | app: &2})
    |> take(kw, :version, ctx, &is_binary/1, &%{&1 | version: &2})
    |> take(kw, :description, ctx, &is_binary/1, &%{&1 | description: &2})
    |> take(kw, :elixirc_paths, ctx, &string_list?/1, &%{&1 | elixirc_paths: &2})
    |> read_deps(Keyword.get(kw, :deps), ctx)
  end

  defp read_application(acc, nil, _ctx), do: acc

  defp read_application(acc, kw, ctx) do
    acc
    |> take(kw, :extra_applications, ctx, &atom_list?/1, &%{&1 | extra_applications: &2})
    |> take(kw, :applications, ctx, &atom_list?/1, &%{&1 | applications: &2})
    |> take(kw, :mod, ctx, &mod?/1, &%{&1 | mod: &2})
    |> read_env(Keyword.get(kw, :env), ctx)
  end

  # `hooks_module` is read on its own so a non-literal sibling does not hide
  # it, and the rest of `env` is kept only when every value is literal.
  defp read_env(acc, nil, _ctx), do: acc

  defp read_env(acc, env_ast, ctx) do
    case keyword_ast(env_ast, ctx) do
      nil ->
        warn(acc, "application env is not a literal keyword list; left out of the .app")

      kw ->
        Enum.reduce(kw, acc, fn {key, value_ast}, acc ->
          case literal(value_ast, ctx) do
            {:ok, value} when key == :hooks_module ->
              put_hooks_module(acc, value)

            {:ok, value} ->
              %{acc | env: [{key, value} | acc.env]}

            :error when key == :hooks_module ->
              warn(acc, "env hooks_module is not a literal; it is detected after compiling")

            :error ->
              warn(acc, "env #{inspect(key)} is not a literal; left out of the .app")
          end
        end)
    end
  end

  defp put_hooks_module(acc, value) when is_atom(value) and value != nil,
    do: %{acc | hooks_module: value}

  defp put_hooks_module(acc, value) when is_binary(value) or is_list(value) do
    with true <- is_binary(value) or List.ascii_printable?(value),
         name when name != "" <- value |> to_string() |> String.trim_leading("Elixir.") do
      %{acc | hooks_module: Module.concat([name])}
    else
      _ -> acc
    end
  end

  defp put_hooks_module(acc, _value), do: acc

  defp take(acc, kw, key, ctx, valid?, put) do
    case Keyword.fetch(kw, key) do
      :error ->
        acc

      {:ok, value_ast} ->
        with {:ok, value} <- literal(value_ast, ctx),
             true <- valid?.(value) do
          put.(acc, value)
        else
          _ -> warn(acc, "#{key} is not a literal; using the default")
        end
    end
  end

  defp read_deps(acc, nil, _ctx), do: acc

  defp read_deps(acc, deps_ast, ctx) do
    case resolve(deps_ast, ctx) do
      entries when is_list(entries) ->
        Enum.reduce(entries, acc, fn entry, acc ->
          case dep(entry, ctx) do
            {:ok, dep} -> %{acc | deps: [dep | acc.deps]}
            :error -> warn(acc, "cannot read the dependency #{Macro.to_string(entry)}")
          end
        end)

      _other ->
        warn(acc, "deps is not a literal list; no dependency is checked")
    end
  end

  # `{:name, requirement}`, `{:name, opts}`, `{:name, requirement, opts}`, or a
  # local helper called with the name first (`shared_dep(:gamend_sdk, path)`),
  # whose options cannot be known and are taken as the defaults.
  defp dep({name, second}, ctx) when is_atom(name), do: dep_with(name, [second], ctx)

  defp dep({:{}, _, [name | rest]}, ctx) when is_atom(name) and rest != [],
    do: dep_with(name, rest, ctx)

  defp dep({fun, _, [name | _]}, _ctx) when is_atom(fun) and is_atom(name) and name != nil,
    do: {:ok, %{name: name, runtime?: true, optional?: false, prod?: true}}

  defp dep(_entry, _ctx), do: :error

  defp dep_with(name, rest, ctx) do
    opts =
      rest
      |> List.last()
      |> literal(ctx)
      |> case do
        {:ok, opts} when is_list(opts) -> if Keyword.keyword?(opts), do: opts, else: []
        _ -> []
      end

    only = opts |> Keyword.get(:only, :prod) |> List.wrap()

    {:ok,
     %{
       name: name,
       runtime?: Keyword.get(opts, :runtime, true) != false,
       optional?: Keyword.get(opts, :optional, false) == true,
       prod?: :prod in only
     }}
  end

  # A keyword list as a list of `{key, value_ast}`, without evaluating values.
  defp keyword_ast(ast, ctx) do
    case resolve(ast, ctx) do
      list when is_list(list) ->
        if Enum.all?(list, &match?({key, _} when is_atom(key), &1)), do: list

      _ ->
        nil
    end
  end

  # Follow local calls and module attributes to the expression they return,
  # without evaluating it.
  defp resolve(_ast, %{depth: depth}) when depth > @max_depth, do: :error

  defp resolve({:@, _, [{name, _, context}]}, ctx) when is_atom(name) and is_atom(context),
    do: Map.get(ctx.attrs, name, :error)

  defp resolve({:||, _, [left, right]}, ctx) do
    case literal(left, ctx) do
      {:ok, value} when value not in [nil, false] -> left
      _ -> resolve(right, ctx)
    end
  end

  defp resolve({name, _, args} = ast, ctx) when is_atom(name) and is_list(args) do
    if Map.has_key?(ctx.defs, {name, length(args)}), do: call_local(name, args, ctx), else: ast
  end

  defp resolve(ast, _ctx), do: ast

  defp call_local(name, args, ctx) do
    ctx = %{ctx | depth: ctx.depth + 1}
    values = Enum.map(args, &literal(&1, ctx))

    ctx.defs
    |> Map.get({name, length(args)}, [])
    |> Enum.find_value(:error, fn {patterns, body} ->
      if clause_matches?(patterns, values), do: resolve(last(body), ctx)
    end)
  end

  defp clause_matches?(patterns, values) do
    patterns
    |> Enum.zip(values)
    |> Enum.all?(fn
      {{var, _, context}, _value} when is_atom(var) and is_atom(context) ->
        true

      {pattern, {:ok, value}} ->
        literal(pattern, %{attrs: %{}, defs: %{}, depth: 0}) == {:ok, value}

      {_pattern, :error} ->
        false
    end)
  end

  defp last(body), do: body |> block() |> List.last()

  # Evaluate a literal term: atoms, numbers, strings, lists, tuples, maps,
  # aliases, charlist/word sigils, `Mix.env()` (as `:prod`), and anything
  # `resolve/2` can follow to one of those.
  defp literal(ast, ctx) do
    case resolve(ast, ctx) do
      :error -> :error
      resolved -> eval(resolved, ctx)
    end
  end

  defp eval(value, _ctx) when is_atom(value) or is_number(value) or is_binary(value),
    do: {:ok, value}

  defp eval(list, ctx) when is_list(list), do: eval_all(list, ctx)

  defp eval({left, right}, ctx) do
    with {:ok, [l, r]} <- eval_all([left, right], ctx), do: {:ok, {l, r}}
  end

  defp eval({:{}, _, elems}, ctx) do
    with {:ok, values} <- eval_all(elems, ctx), do: {:ok, List.to_tuple(values)}
  end

  defp eval({:%{}, _, pairs}, ctx) do
    with {:ok, values} <- eval_all(pairs, ctx), do: {:ok, Map.new(values)}
  end

  defp eval({:__aliases__, _, parts}, _ctx) do
    if Enum.all?(parts, &is_atom/1), do: {:ok, Module.concat(parts)}, else: :error
  end

  defp eval({:-, _, [number]}, _ctx) when is_number(number), do: {:ok, -number}

  defp eval({:sigil_c, _, [{:<<>>, _, [string]}, []]}, _ctx) when is_binary(string),
    do: {:ok, String.to_charlist(string)}

  defp eval({:sigil_w, _, [{:<<>>, _, [string]}, modifiers]}, _ctx) when is_binary(string) do
    words = String.split(string)

    case modifiers do
      ~c"a" -> {:ok, Enum.map(words, &String.to_atom/1)}
      ~c"c" -> {:ok, Enum.map(words, &String.to_charlist/1)}
      mods when mods in [[], ~c"s"] -> {:ok, words}
      _ -> :error
    end
  end

  defp eval({{:., _, [{:__aliases__, _, [:Mix]}, :env]}, _, []}, _ctx), do: {:ok, :prod}
  defp eval(_ast, _ctx), do: :error

  defp eval_all(asts, ctx) do
    Enum.reduce_while(asts, {:ok, []}, fn ast, {:ok, acc} ->
      case literal(ast, ctx) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end

  defp collect_attributes(exprs) do
    for {:@, _, [{name, _, [value]}]} <- exprs, is_atom(name), into: %{}, do: {name, value}
  end

  defp collect_defs(exprs) do
    exprs
    |> Enum.flat_map(fn
      {kind, _, [head, [do: body]]} when kind in [:def, :defp] -> def_clause(head, body)
      _ -> []
    end)
    |> Enum.group_by(fn {key, _clause} -> key end, fn {_key, clause} -> clause end)
  end

  # Clauses with a guard are skipped: which one applies cannot be decided
  # without evaluating it.
  defp def_clause({:when, _, _}, _body), do: []

  defp def_clause({name, _, args}, body) when is_atom(name) do
    args = if is_list(args), do: args, else: []
    [{{name, length(args)}, {args, body}}]
  end

  defp def_clause(_head, _body), do: []

  defp app_name?(value), do: is_atom(value) and value not in [nil, true, false]
  defp string_list?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)
  defp atom_list?(value), do: is_list(value) and Enum.all?(value, &is_atom/1)
  defp mod?({module, _args}), do: is_atom(module)
  defp mod?(_value), do: false

  defp warn(acc, message), do: %{acc | warnings: [message | acc.warnings]}
end
