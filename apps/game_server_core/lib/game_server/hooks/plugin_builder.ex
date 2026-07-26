defmodule GameServer.Hooks.PluginBuilder do
  @moduledoc """
  Builds an OTP plugin bundle from plugin source code on disk.

  This is intended for admin-only workflows in development/self-hosted setups.
  It runs `mix` commands on the server host/container.
  """

  @type step_result :: %{
          cmd: String.t(),
          status: non_neg_integer(),
          output: String.t()
        }

  @type build_result :: %{
          ok?: boolean(),
          plugin: String.t(),
          source_dir: String.t(),
          started_at: DateTime.t(),
          finished_at: DateTime.t(),
          steps: [step_result()]
        }

  @spec sources_dir() :: String.t()
  def sources_dir do
    # Mirror the loader's default (GameServer.Hooks.PluginManager.plugins_dir/0)
    # so the builder always knows where plugin sources live, even when the
    # GAME_SERVER_PLUGINS_DIR env var is unset.
    GameServer.Settings.get(GameServer.ContentSettings, :plugins_dir) ||
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

  @spec build(String.t()) :: {:ok, build_result()} | {:error, term()}
  def build(plugin_name) when is_binary(plugin_name) do
    source_dir = sources_dir()
    plugin_dir = Path.join(source_dir, plugin_name)

    if File.exists?(Path.join(plugin_dir, "mix.exs")) do
      run_build_steps(plugin_name, source_dir, plugin_dir)
    else
      return_error({:missing_mix_project, plugin_dir})
    end
  rescue
    e ->
      {:error, {:build_failed, Exception.message(e)}}
  end

  defp run_build_steps(plugin_name, source_dir, plugin_dir) do
    started_at = DateTime.utc_now()

    env =
      case System.get_env("MIX_ENV") do
        nil -> []
        mix_env -> [{"MIX_ENV", mix_env}]
      end

    steps =
      [
        {"mix deps.get", ["deps.get"]},
        {"mix compile", ["compile"]},
        {"mix plugin.bundle --verbose", ["plugin.bundle", "--verbose"]}
      ]
      |> Enum.map(fn {label, argv} ->
        {output, status} =
          System.cmd("mix", argv,
            cd: plugin_dir,
            env: env,
            stderr_to_stdout: true
          )

        %{cmd: label, status: status, output: output}
      end)

    finished_at = DateTime.utc_now()

    ok? = Enum.all?(steps, &(&1.status == 0))

    {:ok,
     %{
       ok?: ok?,
       plugin: plugin_name,
       source_dir: source_dir,
       started_at: started_at,
       finished_at: finished_at,
       steps: steps
     }}
  end

  defp return_error(reason), do: {:error, reason}
end
