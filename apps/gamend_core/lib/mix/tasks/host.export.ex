defmodule Mix.Tasks.Host.Export do
  use Mix.Task

  @moduledoc false

  @shortdoc "Copies a host's SQLite database and stored files into a folder"

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: [files: :boolean]) do
      {opts, [dir], []} ->
        Mix.Task.run("app.config")
        Gamend.Release.export(dir, opts)

      _usage ->
        Mix.raise("usage: mix host.export DIR [--no-files]")
    end
  end
end
