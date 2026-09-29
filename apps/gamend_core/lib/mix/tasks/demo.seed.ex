defmodule Mix.Tasks.Demo.Seed do
  @shortdoc "Seeds large volumes of demo data (leaderboard, group, tournament)"

  @moduledoc """
  Fills the database with demo data. See `Gamend.DemoSeed` for the sets and
  options; a release runs the same code as `gamend demo.seed`.

      mix demo.seed --count 250 --only leaderboard,group
      mix demo.seed --clean
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Gamend.DemoSeed.run(args)
  rescue
    error in ArgumentError -> Mix.raise(Exception.message(error))
  end
end
