defmodule Mix.Tasks.Gamend.Literal.Lint do
  @shortdoc "Checks for names typed out as strings (CONTRIBUTING.md, Named strings)"

  @moduledoc """
  Flags a string that is really a name (a status, an action, a kind) typed out
  across modules. See `Gamend.LiteralLint` for what counts and for the
  `# literal-ok: <reason>` marker that accepts one.

      mix gamend.literal.lint                    # fail on anything beyond the baseline
      mix gamend.literal.lint --all              # every offender, the known ones too
      mix gamend.literal.lint --update-baseline  # record the counts as they stand now

  Run from the repository root, in the engine or in a host built on it. Only
  this repository's own code is read, never a dependency's. `--update-baseline`
  is for after a migration, when counts have fallen.
  """

  use Mix.Task

  alias Gamend.LiteralLint

  @switches [all: :boolean, update_baseline: :boolean]
  @sites_shown 10

  @impl true
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    offenders = LiteralLint.offenders()

    cond do
      opts[:update_baseline] -> update_baseline(offenders)
      opts[:all] -> list(offenders)
      true -> check(offenders, LiteralLint.read_baseline())
    end
  end

  defp update_baseline(offenders) do
    File.write!(LiteralLint.baseline_file(), LiteralLint.format_baseline(offenders))
    Mix.shell().info("Literal lint: #{length(offenders)} recorded in the baseline")
  end

  defp list(offenders) do
    for %{literal: literal, count: count, modules: modules} <- offenders do
      Mix.shell().info("#{String.pad_leading("#{count}", 5)}  #{modules} modules  #{literal}")
    end

    Mix.shell().info("#{length(offenders)} strings, #{total(offenders)} uses")
  end

  defp check(offenders, baseline) do
    case LiteralLint.new_offenders(offenders, baseline) do
      [] ->
        Mix.shell().info(
          "Literal lint: clean (#{length(offenders)} known, #{total(offenders)} uses)"
        )

      new ->
        Enum.each(new, &report(&1, baseline))

        Mix.raise(
          "#{length(new)} string(s) typed out where a name belongs: give each a name " <>
            "(CONTRIBUTING.md, Named strings), or mark a use `# literal-ok: <why>`"
        )
    end
  end

  defp report(%{literal: literal, count: count, occurrences: occurrences}, baseline) do
    Mix.shell().error(
      "\n#{inspect(literal)}: #{count} uses, #{Map.get(baseline, literal, 0)} known"
    )

    for %{file: file, line: line} <- Enum.take(occurrences, @sites_shown) do
      Mix.shell().error("  #{file}:#{line}")
    end

    if count > @sites_shown, do: Mix.shell().error("  and #{count - @sites_shown} more")
  end

  defp total(offenders), do: offenders |> Enum.map(& &1.count) |> Enum.sum()
end
