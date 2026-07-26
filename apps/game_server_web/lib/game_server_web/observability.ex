defmodule GameServerWeb.Observability do
  @moduledoc """
  Logging, metrics and dashboard settings.

  The admin log buffer is in-memory only, so `log_file_path` is what makes
  history survive a restart. On a platform with ephemeral machines, point it at
  a mounted volume or it goes with the machine.
  """

  use GameServer.Settings.Provider,
    app: :game_server_web,
    group: :observability,
    label: "Observability"

  setting(:log_level, :log_level,
    default: :info,
    doc: "Application log level: debug | info | warning | error."
  )

  setting(:access_log_level, :log_level,
    default: :debug,
    doc: "Level for per-request access logs, or `off` to silence them."
  )

  setting(:log_file_path, :string,
    doc: "Write a rotating log file alongside stdout. Unset disables the file handler."
  )

  setting(:log_file_level, :log_level,
    default: :info,
    doc: "Level for the rotating file handler."
  )

  setting(:log_file_max_bytes, :integer,
    default: 10_000_000,
    doc: "Bytes per rotated file."
  )

  setting(:log_file_max_files, :integer,
    default: 5,
    doc: "How many rotated files to keep. With the default size, ~50MB of disk."
  )

  setting(:metrics_token, :string,
    secret: true,
    doc: "When set, every non-loopback /metrics scrape must send `Authorization: Bearer <token>`."
  )

  setting(:grafana_url, :string,
    doc: "Public Grafana URL linked from the admin dashboard, if you host one."
  )

  @doc "The current value of an observability setting."
  @spec get(atom()) :: term()
  def get(key) when is_atom(key), do: GameServer.Settings.get(__MODULE__, key)
end
