defmodule Mix.Tasks.Host.Seed do
  use Mix.Task

  @moduledoc false

  @shortdoc "Runs the host's priv/repo/seeds.exs when it exists"

  @impl Mix.Task
  def run(_args) do
    case Gamend.Release.seeds_file() do
      nil -> Mix.shell().info("No seeds file at priv/repo/seeds.exs, skipping")
      path -> Mix.Task.run("run", [path])
    end
  end
end
