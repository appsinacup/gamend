defmodule GameServer.Push.FCMDispatcher do
  @moduledoc """
  Pigeon dispatcher for FCM. Configured by `host_runtime.exs` from the
  `PUSH_FCM_*` env vars; started by `GameServer.Push.Supervisor` only when
  that config exists.
  """
  use Pigeon.Dispatcher, otp_app: :game_server_core
end
