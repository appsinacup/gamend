defmodule Mix.Tasks.Gamend.Literal.Lint do
  @shortdoc "Checks for names typed out as strings (CONTRIBUTING.md, Named strings)"

  @moduledoc """
  Flags a string that is really a name (a status, an action, a kind) typed out
  across modules. See `Gamend.LiteralLint` for what counts and for the
  `# literal-ok: <reason>` marker that accepts one.

  Run from the repository root, in the engine or in a host built on it. Only
  this repository's own code is read, never a dependency's.
  """

  use Mix.Task

  alias Gamend.LiteralLint

  @sites_shown 10

  @impl true
  def run(_argv) do
    case LiteralLint.offenders() do
      [] ->
        Mix.shell().info("Literal lint: clean")

      offenders ->
        Enum.each(offenders, &report/1)

        Mix.raise(
          "#{length(offenders)} string(s) typed out where a name belongs: give each a name " <>
            "(CONTRIBUTING.md, Named strings), or mark a use `# literal-ok: <why>`"
        )
    end
  end

  defp report(%{literal: literal, count: count, occurrences: occurrences}) do
    Mix.shell().error("\n#{inspect(literal)}: #{count} uses")

    for %{file: file, line: line} <- Enum.take(occurrences, @sites_shown) do
      Mix.shell().error("  #{file}:#{line}")
    end

    if count > @sites_shown, do: Mix.shell().error("  and #{count - @sites_shown} more")
  end
end
