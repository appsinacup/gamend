defmodule Mix.Tasks.Gamend.Assets do
  @shortdoc "Points a host's stylesheet at Gamend core's"

  @moduledoc """
  Writes `assets/vendor/gamend/`, the pointers a host's `assets/css/app.css`
  loads core's stylesheet and plugins through:

      @import "../vendor/gamend/gamend.css";
      @plugin "../vendor/gamend/daisyui" { themes: false; }
      @plugin "../vendor/gamend/daisyui-theme" { name: "light"; … }

  `gamend.css` (core's `assets/css/gamend.css`) brings Tailwind, core's
  sources, heroicons, core's classes and the base styles of core's pages, so
  a host's stylesheet is only its own look. The pointers are relative paths
  to wherever core is: the sibling `gamend` checkout when `mix.exs` uses it,
  else `deps/gamend_web`. They are generated, so the folder is in the host's
  `.gitignore`; nothing in it is edited by hand.

  The `gamend_assets` compiler runs this on every compile, so dev, tests and
  a Docker build (`mix compile` before `mix assets.deploy`) always have them:

      compilers: Mix.compilers() ++ [:gamend_assets]

      mix gamend.assets          # write the pointers that changed
      mix gamend.assets --check  # fail when they are missing or stale
  """

  use Mix.Task

  @dir "assets/vendor/gamend"
  @marker "Written by `mix gamend.assets`, on every compile. Do not edit."

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [check: :boolean])

    if opts[:check] do
      case stale(File.cwd!()) do
        [] -> Mix.shell().info("Gamend asset pointers are up to date.")
        paths -> Mix.raise("Stale: #{Enum.join(paths, ", ")}. Run `mix gamend.assets`.")
      end
    else
      case write(File.cwd!()) do
        [] -> :ok
        paths -> Mix.shell().info("Wrote #{Enum.join(paths, ", ")}")
      end
    end
  end

  @doc """
  Writes the pointers under `root` that are missing or differ, and answers
  their paths (none when all were current).
  """
  @spec write(Path.t()) :: [Path.t()]
  def write(root) do
    for {path, content} <- files(root), File.read(path) != {:ok, content} do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Path.relative_to(path, root)
    end
  end

  @doc "The pointers under `root` that are missing or differ."
  @spec stale(Path.t()) :: [Path.t()]
  def stale(root) do
    for {path, content} <- files(root), File.read(path) != {:ok, content} do
      Path.relative_to(path, root)
    end
  end

  @doc """
  Each pointer's path under `root` and its content: core's stylesheet, and
  the daisyUI plugins a host configures in its own `app.css`.
  """
  @spec files(Path.t()) :: [{Path.t(), String.t()}]
  def files(root) do
    dir = Path.join(root, @dir)
    core = Path.relative_to(gamend_web_dir!(), dir, force: true)

    [
      {Path.join(dir, "gamend.css"),
       "/* #{@marker} */\n@import \"#{core}/assets/css/gamend.css\";\n"},
      {Path.join(dir, "daisyui.js"),
       "// #{@marker}\nmodule.exports = require(\"#{core}/assets/vendor/daisyui.js\")\n"},
      {Path.join(dir, "daisyui-theme.js"),
       "// #{@marker}\nmodule.exports = require(\"#{core}/assets/vendor/daisyui-theme.js\")\n"}
    ]
  end

  # gamend_web's own directory, the one holding `assets/css/gamend.css`: the
  # dep's root, or its `apps/gamend_web` when the dep is the whole umbrella.
  defp gamend_web_dir! do
    root =
      Mix.Project.deps_paths()[:gamend_web] ||
        Mix.raise("gamend_web is not a dependency of this project: nothing to point at.")

    [root, Path.join(root, "apps/gamend_web")]
    |> Enum.find(&File.regular?(Path.join(&1, "assets/css/gamend.css")))
    |> case do
      nil -> Mix.raise("No assets/css/gamend.css in #{root}: this Gamend predates it.")
      dir -> Path.expand(dir)
    end
  end
end
