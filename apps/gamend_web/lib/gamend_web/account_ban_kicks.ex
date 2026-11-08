defmodule GamendWeb.AccountBanKicks do
  @moduledoc """
  Closes a banned account's open connections, so a ban takes hold at once
  rather than at the next request.

  It listens on `Gamend.Bans.Cache.topic/0`. When an account ban is placed on
  this node it waits `@grace_ms`, so the user channel's `account_banned` push
  is on its way first, then disconnects the account's sockets
  (`user_socket:<id>`, `GamendWeb.UserSocket`) and its open pages (each browser
  session's LiveView topic, `GamendWeb.UserAuth.disconnect_sessions/1`). Both
  reconnect into the banned account's limits: the socket to its user channel
  only, a page to `/suspended`.

  Only the node that placed the ban acts: the endpoint's broadcast reaches the
  connections on every node.
  """

  use GenServer

  require Logger

  alias Gamend.Accounts.Sessions
  alias Gamend.Bans.Cache

  @disconnect "disconnect"

  @grace_ms 500

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Off in tests: the kick reads session tokens, and this process has no
    # sandbox connection. Tests send it messages directly.
    if enabled?(), do: Phoenix.PubSub.subscribe(Gamend.PubSub, Cache.topic())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:bans, :put, {{:account, user_id}, _expires_at}, from_node}, state) do
    if from_node == Node.self(), do: Process.send_after(self(), {:kick, user_id}, @grace_ms)
    {:noreply, state}
  end

  def handle_info({:kick, user_id}, state) do
    kick(user_id)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc "Disconnects `user_id`'s sockets and open pages."
  @spec kick(String.t()) :: :ok
  def kick(user_id) do
    GamendWeb.endpoint().broadcast("user_socket:#{user_id}", @disconnect, %{})
    user_id |> Sessions.session_tokens() |> GamendWeb.UserAuth.disconnect_sessions()
    :ok
  rescue
    e ->
      Logger.error("could not disconnect banned account #{user_id}: " <> Exception.message(e))
      :ok
  end

  defp enabled? do
    :gamend_web
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
