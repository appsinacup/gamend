defmodule Mix.Tasks.Gamend.Race.Lint do
  @shortdoc "Checks for read-then-write shapes that race (AGENTS.md, Locks)"

  @moduledoc """
  Flags functions that keep a rule with a write only an earlier read made
  safe: a state column written on a struct, a count then an insert, a cached
  read deciding a write. See `Gamend.RaceLint` for each check and for the
  `# race-safe: <reason>` marker that accepts one.

      mix gamend.race.lint          # report violations, exit 1 if any
      mix gamend.race.lint --list   # list the checks and exit

  Run from the repository root, in the engine or in a host built on it (a
  host's `lib/` and `modules/` are scanned, and core/web under deps). A host
  registers its own lock helpers as guards:

      config :gamend_core, Gamend.RaceLint, guards: [{:GameCommon, :with_user_lock}]
  """

  use Mix.Task

  alias Gamend.RaceLint

  @impl true
  def run(argv) do
    if "--list" in argv do
      Mix.shell().info("Race checks:\n")
      for {id, desc} <- RaceLint.rules(), do: Mix.shell().info("  #{id}  #{desc}")
    else
      Mix.Task.run("app.config")
      report(RaceLint.violations())
    end
  end

  defp report([]), do: Mix.shell().info("Race lint: clean (#{length(RaceLint.rules())} checks)")

  defp report(violations) do
    for {rule, group} <- Enum.group_by(violations, & &1.rule) do
      Mix.shell().error("\n#{rule} (#{length(group)})")

      for v <- group do
        Mix.shell().error("  #{Path.relative_to_cwd(v.file)}:#{v.line}\n      #{v.message}")
      end
    end

    Mix.raise(
      "#{length(violations)} race lint violation(s); fix them, or mark a safe one " <>
        "`# race-safe: <why>` inside the function"
    )
  end
end
