defmodule Gamend.Signaling do
  @moduledoc """
  WebRTC signaling: who is in a room, and relaying offers between them.

  A "room" is a lobby. There is no room record and no room process — the
  configuration lives in the lobby's own `webrtc_*` columns, membership lives
  in `Gamend.Presence`, and relayed messages travel over `Phoenix.PubSub`.
  All three are cluster-wide, so a peer on one node can signal a peer on
  another.

  That is the reason for this shape. The previous version kept rooms in a
  GenServer registered under a plain local name, so a room created on one node
  did not exist on any other, and every player whose socket landed elsewhere
  failed to join with `:room_not_found`.

  ## Configuration

  Read from the lobby, never mirrored:

      Signaling.configure(lobby, enabled: true, topology: :mesh)
      Signaling.configure(lobby, enabled: true, topology: :star, host_id: some_server_user_id)

  Held in server-owned `lobbies.webrtc_*` columns, written only by
  `configure/2`. It lived in `metadata` once, which was wrong twice over: that
  map is replaced wholesale by any writer, so a game storing match state wiped
  it, and the lobby host can `PATCH` it, so a player could flip the topology and
  hand everyone the right to broadcast. The star host is always
  `lobby.host_id` and is not settable.

  ## Topology

    * `:mesh` — any peer may signal any other.
    * `:star` — every exchange must involve the host, and only the host may
      broadcast.
  """

  require Logger

  alias Gamend.Lobbies
  alias Gamend.Presence

  @stats_cache_ttl_ms 60_000

  @type room_id :: String.t()
  @type user_id :: String.t()
  @type topology :: :mesh | :star
  @type role :: :host | :user
  @type message_type :: :offer | :answer | :ice

  @type config :: %{
          topology: topology(),
          host_user_id: user_id() | nil,
          late_join: boolean(),
          reconnect_timeout: non_neg_integer()
        }

  @default_reconnect_timeout 30_000

  @doc "PubSub topic carrying a room's presence."
  @spec topic(room_id()) :: String.t()
  def topic(room_id), do: "signaling:#{room_id}"

  @doc "PubSub topic one peer listens on for messages addressed to it."
  @spec inbox(room_id(), user_id()) :: String.t()
  def inbox(room_id, user_id), do: "signaling:#{room_id}:#{user_id}"

  @doc """
  The room's configuration, derived from the lobby.

  `{:error, :room_not_found}` when the lobby is gone or WebRTC is not enabled
  on it — deliberately indistinguishable to a caller.
  """
  @spec config(room_id()) :: {:ok, config()} | {:error, :room_not_found}
  def config(room_id) when is_binary(room_id) do
    case Lobbies.get_lobby(room_id) do
      %{webrtc_enabled: true} = lobby ->
        {:ok,
         %{
           topology: parse_topology(lobby.webrtc_topology),
           host_user_id: lobby.webrtc_host_id || lobby.host_id,
           late_join: lobby.webrtc_late_join,
           reconnect_timeout: lobby.webrtc_reconnect_timeout_ms || @default_reconnect_timeout
         }}

      _disabled_or_missing ->
        {:error, :room_not_found}
    end
  end

  @doc """
  Turns signaling on or off for a lobby, and sets how it behaves.

  The only writer of the `webrtc_*` columns. Options: `:enabled`, `:topology`
  (`:star` | `:mesh`), `:late_join`, `:reconnect_timeout`.

  Deliberately not part of the lobby changeset — a client `PATCH` must not be
  able to reach any of it. The star host is not settable at all; it is always
  the lobby host.
  """
  @spec configure(Lobbies.Lobby.t() | room_id(), keyword()) ::
          {:ok, Lobbies.Lobby.t()} | {:error, term()}
  def configure(room_id, opts) when is_binary(room_id) do
    case Lobbies.get_lobby(room_id) do
      nil -> {:error, :not_found}
      lobby -> configure(lobby, opts)
    end
  end

  def configure(lobby, opts) do
    changes =
      %{}
      |> put_opt(opts, :enabled, :webrtc_enabled)
      |> put_opt(opts, :host_id, :webrtc_host_id)
      |> put_opt(opts, :late_join, :webrtc_late_join)
      |> put_opt(opts, :reconnect_timeout, :webrtc_reconnect_timeout_ms)
      |> put_topology(opts)

    Lobbies.write_webrtc_config(lobby, changes)
  end

  defp put_opt(changes, opts, key, field) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Map.put(changes, field, value)
      :error -> changes
    end
  end

  defp put_topology(changes, opts) do
    case Keyword.fetch(opts, :topology) do
      {:ok, topology} -> Map.put(changes, :webrtc_topology, to_string(parse_topology(topology)))
      :error -> changes
    end
  end

  @doc "Whether the lobby has WebRTC enabled."
  @spec enabled?(room_id()) :: boolean()
  def enabled?(room_id), do: match?({:ok, _}, config(room_id))

  @doc """
  The role `user_id` may join with, or `{:error, :not_allowed}`.

  Membership comes from the lobby. `late_join` decides whether a non-member may
  connect at all; the host of a star room is whoever the lobby says it is.
  """
  @spec authorize(room_id(), user_id()) ::
          {:ok, role()} | {:error, :room_not_found | :not_allowed}
  def authorize(room_id, user_id) when is_binary(room_id) and is_binary(user_id) do
    with {:ok, cfg} <- config(room_id) do
      cond do
        cfg.topology == :star and cfg.host_user_id == user_id -> {:ok, :host}
        member?(room_id, user_id) -> {:ok, :user}
        cfg.late_join -> {:ok, :user}
        true -> {:error, :not_allowed}
      end
    end
  end

  @doc """
  Everyone currently connected to the room, as `%{user_id => role}`.

  The role is computed from the lobby on every read rather than read back from
  the presence meta it was tracked with. Otherwise a host change leaves the new
  host tracked as `:user` and the old one still holding `:host` until they
  happen to reconnect.
  """
  @spec peers(room_id()) :: %{user_id() => role()}
  def peers(room_id) when is_binary(room_id) do
    host = with {:ok, %{host_user_id: id}} <- config(room_id), do: id
    peers_with_host(room_id, host)
  end

  # Takes the host rather than looking it up, so the relay path reads the lobby
  # once per message instead of twice.
  defp peers_with_host(room_id, host) do
    room_id
    |> topic()
    |> Presence.list()
    |> Map.new(fn {user_id, _metas} ->
      {user_id, if(user_id == host, do: :host, else: :user)}
    end)
  end

  @doc "The role `user_id` is connected with, or `nil`."
  @spec peer_role(room_id(), user_id()) :: role() | nil
  def peer_role(room_id, user_id), do: Map.get(peers(room_id), user_id)

  @doc """
  Aggregate room counts for the public stats endpoint.

  `rooms_enabled` is what the lobbies are configured for; `rooms_active` counts
  only rooms someone is actually connected to. Presence cannot enumerate its own
  topics, so the room ids come from the lobby table first.
  """
  @spec stats() :: %{
          rooms_enabled: non_neg_integer(),
          rooms_active: non_neg_integer(),
          peers_connected: non_neg_integer()
        }
  def stats do
    Gamend.Cache.cached({:signaling, :stats}, [ttl: @stats_cache_ttl_ms], fn ->
      peer_counts =
        Lobbies.webrtc_enabled_lobby_ids()
        |> Enum.map(fn room_id -> room_id |> topic() |> Presence.list() |> map_size() end)

      %{
        rooms_enabled: length(peer_counts),
        rooms_active: Enum.count(peer_counts, &(&1 > 0)),
        peers_connected: Enum.sum(peer_counts)
      }
    end)
  end

  @doc """
  Sends `payload` to one peer.

  In a star room every exchange must involve the host; in a mesh room any pair
  may talk.
  """
  @spec relay(room_id(), user_id(), user_id(), message_type(), map()) ::
          :ok | {:error, :room_not_found | :user_not_found | :not_allowed}
  def relay(room_id, from, to, type, payload) do
    with {:ok, cfg} <- config(room_id),
         connected = peers_with_host(room_id, cfg.host_user_id),
         {:ok, from_role} <- fetch_peer(connected, from),
         {:ok, to_role} <- fetch_peer(connected, to),
         :ok <- allow_pair(cfg.topology, from_role, to_role) do
      Phoenix.PubSub.broadcast(
        Gamend.PubSub,
        inbox(room_id, to),
        {:signaling_relay, type, from, payload}
      )
    end
  end

  @doc """
  Sends `payload` to every other peer in the room.

  Only the host may broadcast in a star room.
  """
  @spec broadcast(room_id(), user_id(), message_type(), map()) ::
          :ok | {:error, :room_not_found | :user_not_found | :not_allowed}
  def broadcast(room_id, from, type, payload) do
    with {:ok, cfg} <- config(room_id),
         connected = peers_with_host(room_id, cfg.host_user_id),
         {:ok, from_role} <- fetch_peer(connected, from),
         :ok <- allow_broadcast(cfg.topology, from_role) do
      for {user_id, _role} <- connected, user_id != from do
        Phoenix.PubSub.broadcast(
          Gamend.PubSub,
          inbox(room_id, user_id),
          {:signaling_relay, type, from, payload}
        )
      end

      :ok
    end
  end

  @doc "Tells every connected peer the room is over, so their channels stop."
  @spec close(room_id()) :: :ok
  def close(room_id) when is_binary(room_id) do
    Logger.info("Signaling: closing room=#{room_id}")

    for {user_id, _role} <- peers(room_id) do
      Phoenix.PubSub.broadcast(
        Gamend.PubSub,
        inbox(room_id, user_id),
        {:signaling_relay, :room_closed, nil, %{room_id: room_id}}
      )
    end

    :ok
  end

  defp fetch_peer(peers, user_id) do
    case Map.fetch(peers, user_id) do
      {:ok, role} -> {:ok, role}
      :error -> {:error, :user_not_found}
    end
  end

  defp allow_pair(:star, from_role, to_role) when from_role != :host and to_role != :host do
    {:error, :not_allowed}
  end

  defp allow_pair(_topology, _from_role, _to_role), do: :ok

  defp allow_broadcast(:star, role) when role != :host, do: {:error, :not_allowed}
  defp allow_broadcast(_topology, _role), do: :ok

  defp member?(room_id, user_id) do
    case Lobbies.get_lobby(room_id) do
      nil -> false
      lobby -> Enum.any?(Lobbies.get_lobby_members(lobby), &(&1.id == user_id))
    end
  end

  defp parse_topology("mesh"), do: :mesh
  defp parse_topology(:mesh), do: :mesh
  defp parse_topology(_star_by_default), do: :star
end
