defmodule GameServerWeb.FileLogHandler do
  @moduledoc """
  Persists all logs to a rotating file so history survives restarts — the
  admin log buffer (`GameServerWeb.AdminLogBuffer`) is in-memory only and is
  lost on redeploy/restart.

  Disabled unless a path is configured, either as `:game_server_web, :log_file`
  or via the `LOG_FILE_PATH` environment variable. Runs *alongside* the default
  stdout handler, so `fly logs` still receives everything. On a Fly deploy,
  point it at the mounted volume, e.g.
  `LOG_FILE_PATH=/data/log/game_server.log`.

  Backed by OTP's built-in `:logger_std_h`, which handles size-based rotation
  (`max_no_bytes` per file, `max_no_files` kept). Defaults to 10MB x 5 files.

  ## Why the env is read here

  This used to require each host to wire `LOG_FILE_PATH` into `:log_file` in its
  own runtime config. A host loads its own runtime config and never core's, so
  the block core shipped reached only the hosts that had copied it — and the two
  that had not got no file logging at all while the env var looked set. Reading
  the environment here means a host needs no config for this to work. Explicit
  `:game_server_web` app config still wins, so a host can override.

  | setting | app config | env |
  | --- | --- | --- |
  | path | `:log_file` | `LOG_FILE_PATH` |
  | level | `:log_file_level` | `LOG_FILE_LEVEL` |
  | bytes per file | `:log_file_max_bytes` | `LOG_FILE_MAX_BYTES` |
  | files kept | `:log_file_max_files` | `LOG_FILE_MAX_FILES` |
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

  defp configured_path, do: GameServerWeb.Observability.get(:log_file_path)

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
        max_no_bytes: GameServerWeb.Observability.get(:log_file_max_bytes),
        max_no_files: GameServerWeb.Observability.get(:log_file_max_files),
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

  defp log_level, do: GameServerWeb.Observability.get(:log_file_level)
end
