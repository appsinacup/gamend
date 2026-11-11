defmodule Mix.Tasks.Compile.GamendAssets do
  @shortdoc "Keeps a host's pointers to Gamend core's stylesheet current"

  @moduledoc """
  Runs `mix gamend.assets` on every compile, so `assets/vendor/gamend/` is
  there before Tailwind runs: the dev server's watcher, `mix assets.build`
  and a Docker build's `mix assets.deploy` all come after a compile. A host
  adds it once:

      compilers: Mix.compilers() ++ [:gamend_assets]

  Writes nothing when the pointers are current, and nothing in a project
  with no `assets/css`.
  """

  use Mix.Task.Compiler

  @impl Mix.Task.Compiler
  def run(_args) do
    root = File.cwd!()

    cond do
      not File.dir?(Path.join(root, "assets/css")) -> {:noop, []}
      Mix.Tasks.Gamend.Assets.write(root) == [] -> {:noop, []}
      true -> {:ok, []}
    end
  end
end
