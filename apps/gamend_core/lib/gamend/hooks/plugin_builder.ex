defmodule Gamend.Hooks.PluginBuilder do
  @moduledoc """
  Builds an OTP plugin bundle (`ebin/*.beam` + `ebin/<app>.app`) from plugin
  source code on disk, for the admin Config page and the command line.

  Two ways, picked per build:

    * **Mix**, when a `mix` executable is on the PATH (development, the
      Dockerfile's `full` image): `mix deps.get`, `mix gamend.gdscript.compile`
      for a GDScript plugin, `mix compile`, `mix plugin.bundle`, each in the
      plugin's directory.
    * **In-process**, when it is not (a release: the downloadable engine, the
      `release` image): `Gamend.Hooks.PluginBuilder.InProcess` compiles the
      plugin inside the running VM with the Elixir compiler the release ships.
      It handles Elixir and GDScript plugins whose dependencies the engine
      already ships or the plugin carries prebuilt under `deps/<dep>/ebin`.

  Either way the result loads through `Gamend.Hooks.PluginManager` exactly as
  a hand-built bundle does. Building runs the plugin's code (its `mix.exs`
  under Mix, its module bodies in both), so this is for admins and the
  operator's shell only.
  """

  alias Gamend.Hooks.PluginBuilder.InProcess

  @type step_result :: %{
          cmd: String.t(),
          status: non_neg_integer(),
          output: String.t()
        }

  @type mode :: :mix | :in_process

  @type build_result :: %{
          ok?: boolean(),
          plugin: String.t(),
          source_dir: String.t(),
          mode: mode(),
          started_at: DateTime.t(),
          finished_at: DateTime.t(),
          steps: [step_result()]
        }

  @doc """
  Whether this image can build plugin bundles at all: with `mix`, or in-process
  with the Elixir compiler.

  The in-process build needs only the `elixir` and `compiler` applications,
  which every release carries (`elixir` depends on `compiler`), so this is
  true in a release too. Callers still check it so an image without either
  presents a disabled control with a reason rather than a failed build.
  """
  @spec available?() :: boolean()
  def available?, do: mode() != nil

  @doc """
  How `build/1` would build here: `:mix` when this server itself runs under
  Mix and a `mix` executable is on the PATH, else `:in_process` when the
  compiler is loadable, else `nil`.

  A release builds in-process even with a `mix` on the PATH: that one belongs
  to some other Elixir install, and started from a release it inherits the
  release's ERTS environment (`ROOTDIR`, `BINDIR`) and fails to boot.
  """
  @spec mode() :: mode() | nil
  def mode do
    cond do
      mix_available?() -> :mix
      InProcess.available?() -> :in_process
      true -> nil
    end
  end

  defp mix_available? do
    Code.ensure_loaded?(Mix.Project) and System.find_executable("mix") != nil
  end

  @spec sources_dir() :: String.t()
  def sources_dir do
    # Mirror the loader's default (Gamend.Hooks.PluginManager.plugins_dir/0)
    # so the builder always knows where plugin sources live, even when the
    # GAMEND_CONTENT_PLUGINS_DIR env var is unset.
    Gamend.Settings.get(Gamend.ContentSettings, :plugins_dir) ||
      Path.expand("modules/plugins")
  end

  @spec list_buildable_plugins() :: [String.t()]
  def list_buildable_plugins do
    dir = sources_dir()

    with true <- File.dir?(dir),
         {:ok, entries} <- File.ls(dir) do
      entries
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.filter(fn p ->
        File.dir?(p) and File.exists?(Path.join(p, "mix.exs"))
      end)
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()
    else
      _ -> []
    end
  end

  @doc """
  Builds one plugin from `sources_dir/0`.

  Returns `{:ok, result}` for every build that ran, successful or not
  (`result.ok?` tells, and `result.steps` carries each step's output: compiler
  errors, missing dependencies), and `{:error, reason}` when none could run:
  `{:unknown_plugin, name}`, `:mix_unavailable`, `:build_unavailable`.

  Options:

    * `:mode` - `:auto` (default: Mix when on the PATH, else in-process),
      `:mix` or `:in_process`.

  A plugin the manager has loaded is stopped for an in-process build and
  started again when it ends (see `Gamend.Hooks.PluginBuilder.InProcess`). A
  Mix build leaves it running; `PluginManager.reload/0` picks the new bundle up.
  """
  @spec build(String.t(), keyword()) :: {:ok, build_result()} | {:error, term()}
  def build(plugin_name, opts \\ []) when is_binary(plugin_name) do
    source_dir = sources_dir()

    # The name has to be one of the plugins we actually offer, checked here
    # rather than only at the caller.
    #
    # `mix compile` *evaluates* the `mix.exs` in its working directory, and
    # `mix deps.get` fetches whatever refs that file names — so a directory is
    # not an innocent parameter, it is code. The admin LiveView passed a
    # client-controlled string straight through (the rendered `<select>` does
    # not constrain the event payload), and this function joined it onto the
    # sources directory with no basename and no allowlist, so
    # `../../../../tmp/x` reached `System.cmd`. Arguments are passed as a list,
    # so there was never a shell-injection hole; the working directory was the
    # whole vulnerability. The in-process build compiles the directory's code
    # in this VM, which makes the allowlist no less necessary.
    plugin_name = Path.basename(plugin_name)
    plugin_dir = Path.join(source_dir, plugin_name)

    with {:ok, mode} <- pick_mode(Keyword.get(opts, :mode, :auto)) do
      cond do
        plugin_name not in list_buildable_plugins() ->
          {:error, {:unknown_plugin, plugin_name}}

        File.exists?(Path.join(plugin_dir, "mix.exs")) ->
          run_build(mode, plugin_name, source_dir, plugin_dir)

        true ->
          {:error, {:missing_mix_project, plugin_dir}}
      end
    end
  rescue
    e ->
      {:error, {:build_failed, Exception.message(e)}}
  end

  @doc """
  Builds every plugin `list_buildable_plugins/0` offers, one after another,
  and returns `[{name, build_result}]` in that order. Takes the options of
  `build/2`.
  """
  @spec build_all(keyword()) :: [{String.t(), {:ok, build_result()} | {:error, term()}}]
  def build_all(opts \\ []) do
    for name <- list_buildable_plugins(), do: {name, build(name, opts)}
  end

  defp pick_mode(:auto) do
    case mode() do
      nil -> {:error, :build_unavailable}
      mode -> {:ok, mode}
    end
  end

  defp pick_mode(:mix) do
    if mix_available?(), do: {:ok, :mix}, else: {:error, :mix_unavailable}
  end

  defp pick_mode(:in_process) do
    if InProcess.available?(), do: {:ok, :in_process}, else: {:error, :build_unavailable}
  end

  defp run_build(mode, plugin_name, source_dir, plugin_dir) do
    started_at = DateTime.utc_now()

    steps =
      case mode do
        :mix -> run_mix_steps(plugin_dir)
        :in_process -> InProcess.run(plugin_name, plugin_dir)
      end

    {:ok,
     %{
       ok?: steps != [] and Enum.all?(steps, &(&1.status == 0)),
       plugin: plugin_name,
       source_dir: source_dir,
       mode: mode,
       started_at: started_at,
       finished_at: DateTime.utc_now(),
       steps: steps
     }}
  end

  defp run_mix_steps(plugin_dir) do
    env =
      case System.get_env("MIX_ENV") do
        nil -> []
        mix_env -> [{"MIX_ENV", mix_env}]
      end

    # A GDScript plugin compiles `gen/`, which is generated from `scripts/`;
    # without this step the build would bundle whatever `gen/` held.
    gdscript =
      if InProcess.gdscript_scripts(plugin_dir) != [],
        do: [{"mix gamend.gdscript.compile", ["gamend.gdscript.compile"]}],
        else: []

    ([{"mix deps.get", ["deps.get"]}] ++
       gdscript ++
       [
         {"mix compile", ["compile"]},
         {"mix plugin.bundle --verbose", ["plugin.bundle", "--verbose"]}
       ])
    |> Enum.map(fn {label, argv} ->
      {output, status} =
        System.cmd("mix", argv,
          cd: plugin_dir,
          env: env,
          stderr_to_stdout: true
        )

      %{cmd: label, status: status, output: output}
    end)
  end
end
