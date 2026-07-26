defmodule GameServer.Push.APNSDispatcher do
  @moduledoc """
  Pigeon dispatcher for APNs. Configured by `host_runtime.exs` from the
  `APNS_*` env vars; started by `GameServer.Push.Supervisor` only when that
  config exists.
  """
  use Pigeon.Dispatcher, otp_app: :game_server_core
end
