defmodule GamendWeb.FileLogHandler do
  @moduledoc """
  Persists all logs to a rotating file so history survives restarts — the
  admin log buffer (`GamendWeb.AdminLogBuffer`) is in-memory only and is
  lost on redeploy/restart.

  Disabled unless a path is configured. Runs *alongside* the default stdout
  handler, so `fly logs` still receives everything. On a Fly deploy, point it at
  the mounted volume.

      config :gamend_web, GamendWeb.Observability, log_file_path: "log/dev.log"

  Backed by OTP's built-in `:logger_std_h`, which handles size-based rotation
  (`max_no_bytes` per file, `max_no_files` kept). Defaults to 10MB x 5 files.

  ## Where the settings come from

  Every knob is a declared `GamendWeb.Observability` setting, so it is read
  through `Gamend.Settings.get/2` — which looks at
  `Application.get_env(:gamend_web, GamendWeb.Observability)` and then the
  compiled default. **Nothing else.** In particular `get/2` does not read the
  environment: a host that wants env-driven settings has to splat
  `Gamend.Settings.from_env/0` into its own `runtime.exs`, and a host that does
  not gets app config only, however the variables are set.

  | setting | config key | env (only via `from_env/0`) |
  | --- | --- | --- |
  | path | `:log_file_path` | `GAMEND_OBSERVABILITY_LOG_FILE_PATH` |
  | level | `:log_file_level` | `GAMEND_OBSERVABILITY_LOG_FILE_LEVEL` |
  | bytes per file | `:log_file_max_bytes` | `GAMEND_OBSERVABILITY_LOG_FILE_MAX_BYTES` |
  | files kept | `:log_file_max_files` | `GAMEND_OBSERVABILITY_LOG_FILE_MAX_FILES` |

  An unconfigured path disables the handler *silently*: the host logs to
  stdout only and loses every run to terminal scrollback.

  A misconfigured path is silent by design — this handler must never be
  the reason a boot fails — so when adding a knob here, prefer one whose
  absence is visible in `GamendWeb.Observability` rather than only at runtime.
  """

  require Logger

  @handler_id :file_log

  @doc """
  Installs the file handler when a log file path is configured. Idempotent —
  calling it again while already installed is a no-op.
  """
  def install do
    with path when is_binary(path) and path != "" <- configured_path(),
         :undefined <- handler_status() do
      add_handler(path)
    else
      _ -> :ok
    end
  end

  defp configured_path, do: GamendWeb.Observability.get(:log_file_path)

  defp handler_status do
    case :logger.get_handler_config(@handler_id) do
      {:ok, _config} -> :installed
      {:error, _reason} -> :undefined
    end
  end

  defp add_handler(path) do
    _ = File.mkdir_p(Path.dirname(path))

    config = %{
      level: log_level(),
      config: %{
        file: String.to_charlist(path),
        max_no_bytes: GamendWeb.Observability.get(:log_file_max_bytes),
        max_no_files: GamendWeb.Observability.get(:log_file_max_files),
        filesync_repeat_interval: 5_000
      },
      formatter:
        Logger.Formatter.new(
          format: "$date $time [$level] $metadata$message\n",
          metadata: [:module, :request_id]
        )
    }

    case :logger.add_handler(@handler_id, :logger_std_h, config) do
      :ok ->
        Logger.info("file log handler writing to #{path}")
        :ok

      {:error, {:already_exist, _}} ->
        :ok

      {:error, reason} ->
        Logger.warning("file log handler install failed: #{inspect(reason)}")
        :ok
    end
  end

  defp log_level, do: GamendWeb.Observability.get(:log_file_level)
end
