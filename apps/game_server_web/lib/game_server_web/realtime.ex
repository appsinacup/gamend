defmodule GameServerWeb.Realtime do
  @moduledoc """
  Tuning for outbound realtime state updates.
  """

  use GameServer.Settings.Provider,
    app: :game_server_web,
    group: :realtime,
    label: "Realtime"

  # Each message costs ~76 bytes of WebSocket/TLS/TCP/IP headers before any
  # payload, so coalescing a burst saves more than shrinking payloads does.
  setting(:debounce_ms, :integer,
    default: 0,
    doc:
      "Hold outbound state updates this long and push only the latest per object. 0 pushes immediately."
  )
end
