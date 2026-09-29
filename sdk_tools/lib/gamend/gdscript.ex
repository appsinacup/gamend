defmodule Gamend.GDScript do
  @moduledoc """
  Compile GDScript hook scripts to Elixir source.

      GDScript  ->  lexer  ->  AST  ->  codegen  ->  .ex  ->  mix compile  ->  .beam

  The generated `.ex` is written to disk and kept. It is formatted, readable,
  and it is what appears in stack traces -- so a script author debugs generated
  Elixir that reads like their GDScript, rather than an opaque runtime.

  Nothing is interpreted at run time. The output is ordinary Elixir that
  compiles to the same BEAM bytecode a hand-written plugin does.

  ## Supported subset

  `func` with default arguments, `var` / `const`, assignment and the compound
  operators, `if` / `elif` / `else`, `return`, arithmetic, comparison, `and` /
  `or` / `not`, arrays, dictionaries, indexing, field access, calls into the
  gamend contexts (`Economy.grant(...)`), and calls to other `func`s in the
  same file. Also `for` / `while` / `break` / `continue`, `match` (including
  array and dictionary patterns), `class_name`, inner `class`, `enum`,
  `signal`, `static func` and `await` -- see the GDScript hooks guide for how
  each maps to Elixir.

  Anything else -- `yield`, `export`, `onready`, `tool`, engine types -- is a
  compile error naming the line. There is no best-effort mode: a construct is
  either translated exactly or refused.
  """

  alias Gamend.GDScript.Codegen
  alias Gamend.GDScript.Lexer
  alias Gamend.GDScript.Parser
  alias Gamend.GDScript.Registry

  @doc """
  Compile GDScript source into Elixir source for `module`.

  Raises `Gamend.GDScript.CompileError` with a file and line for anything
  outside the supported subset.
  """
  @spec compile_string(String.t(), String.t(), keyword()) :: String.t()
  def compile_string(source, module, opts \\ []) do
    file = Keyword.get(opts, :file, "nofile")

    source
    |> Lexer.tokenize(file)
    |> Parser.parse(file)
    |> Codegen.generate(module, Keyword.put(opts, :file, file))
  end

  @doc """
  Compile every script in a plugin together, returning
  `[{module_name, elixir_source}]`.

  Scripts are parsed first and then generated, so a script naming itself with
  `class_name Foo` is reachable from every other one as `Foo.method(...)` --
  Godot's own mechanism -- and a wrong name or argument count across files is
  still a compile error.

  Reference mode is decided once for the whole plugin: a reference handed from
  one script to another has to stay a reference, and mixing modes across files
  would break that.

  Options:

    * `:root` - the directory `paths` are relative to. Each file is read from
      `Path.join(root, path)`, while `path` as given is what errors and the
      generated header name. The server's in-process build uses it to produce
      the same `gen/` as `mix gamend.gdscript.compile` run inside the plugin,
      without changing the VM's working directory.
  """
  @spec compile_all([Path.t()], keyword()) :: [{String.t(), String.t()}]
  def compile_all(paths, opts \\ []) do
    root = Keyword.get(opts, :root)

    parsed =
      Enum.map(paths, fn path ->
        module = Keyword.get_lazy(opts, :module, fn -> default_module(path) end)

        statements =
          path
          |> in_root(root)
          |> File.read!()
          |> Lexer.tokenize(path)
          |> Parser.parse(path)

        {path, module, statements}
      end)

    scripts = Enum.map(parsed, fn {_path, module, statements} -> {module, statements} end)
    registry = Registry.build(scripts)
    ref_mode? = Registry.ref_mode?(scripts, &Codegen.mutates?/1)

    Enum.map(parsed, fn {path, module, statements} ->
      {module,
       Codegen.generate(statements, module, file: path, scripts: registry, ref_mode?: ref_mode?)}
    end)
  end

  @doc """
  Compile `path` and return `{module_name, elixir_source}`.

  The module name defaults to `Gamend.Modules.<CamelizedBasename>`, matching
  where a hand-written plugin puts its hooks module.
  """
  @spec compile_file(Path.t(), keyword()) :: {String.t(), String.t()}
  def compile_file(path, opts \\ []) do
    module = Keyword.get_lazy(opts, :module, fn -> default_module(path) end)
    source = File.read!(path)
    {module, compile_string(source, module, file: path)}
  end

  @doc "The module name a script compiles to when none is given."
  @spec default_module(Path.t()) :: String.t()
  def default_module(path) do
    name =
      path
      |> Path.basename(".gd")
      |> String.split(~r/[_\-]/)
      |> Enum.map_join(&String.capitalize/1)

    "Gamend.Modules." <> name
  end

  @doc """
  Where the generated source for `module` goes, relative to the output
  directory: `Gamend.Modules.Shop` -> `gamend/modules/shop.ex`, the layout
  `mix compile` expects and the one a hand-written plugin already uses.
  """
  @spec source_path(String.t()) :: Path.t()
  def source_path(module) do
    module
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
    |> Kernel.<>(".ex")
  end

  defp in_root(path, nil), do: path
  defp in_root(path, root), do: Path.join(root, path)
end
