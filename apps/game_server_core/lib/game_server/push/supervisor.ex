defmodule GameServer.Push.Supervisor do
  @moduledoc """
  Supervises the push delivery processes: the Goth worker (FCM OAuth) and the
  two Pigeon dispatchers.

  Children are built from config, so with nothing configured (or with
  `PUSH_ADAPTER=log`) this supervises nothing and every delivery routes to
  the `Log` provider. Its own restart budget also isolates the app: a
  dispatcher that somehow crash-loops exhausts this supervisor, provider
  `configured?/0` checks start returning false, and push degrades to `Log`
  while the rest of the server runs on.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Supervisor.init(children(), strategy: :one_for_one)
  end

  defp children do
    if GameServer.Push.force_log?() do
      []
    else
      fcm_children() ++ apns_children()
    end
  end

  defp fcm_children do
    case Application.get_env(:game_server_core, GameServer.Push.FCMDispatcher) do
      nil -> []
      config -> List.flatten([goth_children(config), GameServer.Push.FCMDispatcher])
    end
  end

  # The Sandbox adapter (tests) needs no auth, so Goth only starts when the
  # real FCM adapter does.
  defp goth_children(config) do
    goth_config = Application.get_env(:game_server_core, GameServer.Push.Goth)

    if config[:adapter] == Pigeon.FCM and goth_config != nil do
      [{Goth, Keyword.put(goth_config, :name, GameServer.Push.Goth)}]
    else
      []
    end
  end

  defp apns_children do
    case Application.get_env(:game_server_core, GameServer.Push.APNSDispatcher) do
      nil -> []
      _config -> [GameServer.Push.APNSDispatcher]
    end
  end
end
