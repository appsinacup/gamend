defmodule Gamend.Accounts.Online do
  @moduledoc """
  A player online, one way for every client. The SDK's game socket
  (`GamendWeb.UserChannel`) and a host's own page (a LiveView the player
  plays in) call the same functions, so `users.is_online`, friends' online
  dots, lobby, party and group presence, matchmaking's offline prune and the
  abandoned-lobby reaper see them alike.

    * `connected/3`: the socket's process tracked on the user's presence
      topic (`Gamend.Presence.users_topic/1`) with its kind (`"socket"` or
      `"page"`), `users.is_online` set, the user's lobby, party and groups
      told, and the game's `after_socket_connected/3` called.
    * `heartbeat/1`: `last_seen_at` refreshed. A socket calls it every
      `heartbeat_ms/0`, so `StalePresenceSweeper` leaves a live player alone.
    * `disconnected/2`: when no other socket of theirs is left, the user's
      matchmaking tickets cancelled (an accept they were asked for declined)
      and `users.is_online` cleared. Checked again a moment later for a
      socket another node had not replicated yet.

  `watch/2` does all three (as a `"page"`) for a process with no `terminate/2` to rely on:
  a LiveView's is not called when the process is killed or crashes. It
  monitors the process, keeps its heartbeat and runs `disconnected/2` when
  it goes. A node going down takes its watchers with it, and
  `StalePresenceSweeper` marks those players offline.

      config :gamend_core, Gamend.Accounts.Online, watch: false

  leaves `watch/2` at `connected/2`, with no watcher (tests: a watcher outlives
  the test's database sandbox, and its writes fail once the test is done).
  """

  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.StalePresenceSweeper
  alias Gamend.Accounts.User
  alias Gamend.Groups
  alias Gamend.Lobbies
  alias Gamend.Parties

  @page "page"
  @socket "socket"

  @supervisor Gamend.Accounts.Online.Watchers

  # Long enough for a cross-node tracker diff to land, short enough that a
  # player really gone is not shown online meanwhile.
  @recheck_ms 2_000

  @doc """
  `pid`, a socket of `user_id`'s, is open: tracked on the user's presence
  topic (its meta `kind`: `"socket"`, a client's `UserChannel`, or `"page"`,
  a host's page, `watch/2`), `users.is_online` set, the user's lobby, party
  and groups told, and the game's `after_socket_connected/3` called with it,
  every socket (`after_user_online/1` is once a session). Answers the user as
  written, or `{:error, reason}` when the account is gone.
  """
  @spec connected(pid(), Ecto.UUID.t(), String.t()) :: {:ok, User.t()} | {:error, term()}
  def connected(pid, user_id, kind \\ @socket)
      when is_pid(pid) and is_binary(user_id) and kind in [@socket, @page] do
    # Presence is the source of truth for "connected"; `users.is_online` is a
    # projection of it (`Gamend.Presence`). Tracking the socket rather than
    # setting the flag alone is what makes a second socket on another node
    # count.
    case Gamend.Presence.track(pid, Gamend.Presence.users_topic(user_id), user_id, %{
           online_at: System.system_time(:second),
           kind: kind
         }) do
      {:ok, _ref} -> :ok
      {:error, {:already_tracked, _pid, _topic, _key}} -> :ok
    end

    case Accounts.set_user_online(user_id) do
      {:ok, user} ->
        broadcast_member_presence(user_id, true)

        # The game hears each socket, so it can register it where it needs
        # (a presence of its own on the socket's process): a client tells it
        # nothing, the connection is the registration.
        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_socket_connected, [user, pid, kind])
        end)

        {:ok, user}

      error ->
        error
    end
  end

  @doc "A socket of `user_id`'s is still open: `last_seen_at` refreshed."
  @spec heartbeat(Ecto.UUID.t()) :: :ok
  def heartbeat(user_id) when is_binary(user_id) do
    _ = Accounts.touch_last_seen_by_id(user_id)
    :ok
  end

  @doc "How often an open socket calls `heartbeat/1`."
  @spec heartbeat_ms() :: pos_integer()
  def heartbeat_ms, do: StalePresenceSweeper.heartbeat_ms()

  @doc """
  `pid`, a socket of `user_id`'s, closed (or is closing). With no other
  socket of theirs left, their matchmaking tickets are cancelled,
  `users.is_online` is cleared and their lobby, party and groups told, then
  checked again after a moment and the flag put back if a socket is there
  after all.
  """
  @spec disconnected(Ecto.UUID.t(), pid()) :: :ok
  def disconnected(user_id, pid) when is_binary(user_id) and is_pid(pid) do
    if Gamend.Presence.other_socket?(user_id, pid) do
      :ok
    else
      # Their last socket: out of the queue, as a ticket must belong to
      # someone who can be seated. Not before: a reload, a second tab or the
      # game beside the website closes one socket of several, and the player
      # is still there to answer a match.
      _ = Gamend.Matchmaking.cancel(user_id)

      case Accounts.set_user_offline(user_id) do
        {:ok, _} -> broadcast_member_presence(user_id, false)
        _ -> :ok
      end

      recheck(user_id, pid)
    end
  end

  # `Phoenix.Tracker` replicates between nodes asynchronously: a socket that
  # closed on one node just after another opened on a second reads as the
  # last one. Nothing else would put the flag back (`connected/2` runs only on
  # a connect, the stale sweeper only marks people offline), so they showed
  # offline to every friend, lobby and group until they reconnected.
  defp recheck(user_id, pid) do
    Gamend.Async.run(fn ->
      Process.sleep(@recheck_ms)

      if Gamend.Presence.other_socket?(user_id, pid) do
        case Accounts.set_user_online(user_id) do
          {:ok, _} -> broadcast_member_presence(user_id, true)
          _ -> :ok
        end
      end
    end)
  end

  @doc """
  `pid` (a LiveView, any process with no `terminate/2` to rely on) is a
  socket of `user_id`'s for as long as it lives: `connected/2` now, a
  `heartbeat/1` every `heartbeat_ms/0`, `disconnected/2` when it ends however
  it ends. One watcher process per socket, under its own supervisor.
  """
  @spec watch(pid(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def watch(pid, user_id) when is_pid(pid) and is_binary(user_id) do
    with {:ok, _user} <- connected(pid, user_id, @page) do
      if watching?(), do: start_watcher(pid, user_id), else: :ok
    end
  end

  defp watching?, do: Application.get_env(:gamend_core, __MODULE__, [])[:watch] != false

  # No supervisor (a partial tree): online until the stale sweeper notices,
  # which is what a node going down leaves anyway.
  defp start_watcher(pid, user_id) do
    with supervisor when is_pid(supervisor) <- Process.whereis(@supervisor),
         {:ok, _watcher} <-
           Task.Supervisor.start_child(supervisor, fn -> watching(pid, user_id) end) do
      :ok
    else
      nil ->
        :ok

      {:error, reason} = error ->
        Logger.error("online: no watcher for #{user_id}: #{inspect(reason)}")
        error
    end
  end

  defp watching(pid, user_id) do
    ref = Process.monitor(pid)
    loop(ref, pid, user_id)
  end

  defp loop(ref, pid, user_id) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> disconnected(user_id, pid)
    after
      heartbeat_ms() ->
        heartbeat(user_id)
        loop(ref, pid, user_id)
    end
  end

  defp broadcast_member_presence(user_id, online?) do
    event = if online?, do: :member_online, else: :member_offline

    case Accounts.get_user(user_id) do
      %User{} = user ->
        if user.lobby_id, do: Lobbies.broadcast_member_presence(user.lobby_id, {event, user_id})
        if user.party_id, do: Parties.broadcast_member_presence(user.party_id, {event, user_id})

        for group_id <- Groups.user_group_ids(user_id) do
          Groups.broadcast_member_presence(group_id, {event, user_id})
        end

        :ok

      nil ->
        :ok
    end
  end
end
