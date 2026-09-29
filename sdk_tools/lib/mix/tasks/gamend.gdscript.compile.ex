defmodule Mix.Tasks.Gamend.Gdscript.Compile do
  use Mix.Task

  @shortdoc "Compiles scripts/*.gd into gen/*.ex"

  @moduledoc """
  Compiles every `scripts/*.gd` in the current plugin into Elixir source under
  `gen/`.

      mix gamend.gdscript.compile
      mix gamend.gdscript.compile --check

  The generated files are committed, not build output: they are what stack
  traces name, and reviewing their diff is how a codegen change gets reviewed.

  `--check` regenerates in memory and fails if anything on disk differs, which
  is the CI gate against a stale `gen/` -- the same shape as
  `mix gamend.settings.env_example --check`.

  Options:

    * `--check`   - verify `gen/` is up to date, write nothing
    * `--src`     - script directory (default `scripts`)
    * `--out`     - output directory (default `gen`)
  """

  alias Gamend.GDScript

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [check: :boolean, src: :string, out: :string])

    src = Keyword.get(opts, :src, "scripts")
    out = Keyword.get(opts, :out, "gen")
    check? = Keyword.get(opts, :check, false)

    scripts = Path.wildcard(Path.join(src, "*.gd"))

    if scripts == [] do
      Mix.shell().info("no .gd scripts found in #{src}/")
    end

    # Compiled together, so `class_name` makes a script reachable from the
    # others and cross-file calls are checked.
    compiled = GDScript.compile_all(scripts)
    stale = Enum.filter(compiled, &write_or_check(&1, out, check?))

    cond do
      not check? ->
        :ok

      stale == [] ->
        Mix.shell().info("gen/ is up to date (#{length(scripts)} script(s))")

      true ->
        Mix.raise("""
        gen/ is stale for: #{Enum.map_join(stale, ", ", &elem(&1, 0))}

        Run `mix gamend.gdscript.compile` and commit the result.
        """)
    end
  end

  # Returns true when the file on disk does not match what we just generated.
  defp write_or_check({module, source}, out, check?) do
    target = Path.join(out, GDScript.source_path(module))

    if check? do
      File.read(target) != {:ok, source}
    else
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, source)
      Mix.shell().info("compiled -> #{target}")
      false
    end
  end
end
