defmodule Mix.Tasks.Gamend.Time.Lint do
  @shortdoc "Checks for times a page formats by hand (CONTRIBUTING.md, Time)"

  @moduledoc """
  Flags a date, an instant or a relative phrase a page writes out by hand
  instead of through `<.timestamp>`, `<.duration>` or `GamendWeb.TimeText`.
  See `Gamend.TimeLint` for what counts and for the `# time-ok: <reason>`
  marker that accepts one.

  Run from the repository root, in the engine or in a host built on it. Only
  this repository's own code is read, never a dependency's.
  """

  use Mix.Task

  alias Gamend.TimeLint

  @impl true
  def run(_argv) do
    case TimeLint.offenses() do
      [] ->
        Mix.shell().info("Time lint: clean")

      offenses ->
        Enum.each(offenses, fn %{file: file, line: line, rule: rule, text: text} ->
          Mix.shell().error("#{file}:#{line} [#{rule}] #{text}")
        end)

        Mix.raise(
          "#{length(offenses)} time(s) formatted by hand: use <.timestamp>, <.duration> or " <>
            "GamendWeb.TimeText (CONTRIBUTING.md, Time), or mark a use `# time-ok: <why>`"
        )
    end
  end
end
