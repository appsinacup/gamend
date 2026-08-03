defmodule Gamend.Signaling do
  @moduledoc ~S"""
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
  

  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type config() :: %{
  topology: topology(),
  host_user_id: user_id() | nil,
  late_join: boolean(),
  reconnect_timeout: non_neg_integer()
}
  @type message_type() :: :offer | :answer | :ice
  @type role() :: :host | :user
  @type topology() :: :mesh | :star
  @type user_id() :: String.t()
  @type room_id() :: String.t()

  @doc ~S"""
    The role `user_id` may join with, or `{:error, :not_allowed}`.
    
    Membership comes from the lobby. `late_join` decides whether a non-member may
    connect at all; the host of a star room is whoever the lobby says it is.
    
  """
  @spec authorize(room_id(), user_id()) :: {:ok, role()} | {:error, :room_not_found | :not_allowed}
  def authorize(_room_id, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Signaling.authorize/2 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    Sends `payload` to every other peer in the room.
    
    Only the host may broadcast in a star room.
    
  """
  @spec broadcast(room_id(), user_id(), message_type(), map()) ::
  :ok | {:error, :room_not_found | :user_not_found | :not_allowed}
  def broadcast(_room_id, _from, _type, _payload) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Signaling.broadcast/4 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    Tells every connected peer the room is over, so their channels stop.
  """
  @spec close(room_id()) :: :ok
  def close(_room_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Signaling.close/1 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    The room's configuration, derived from the lobby.
    
    `{:error, :room_not_found}` when the lobby is gone or WebRTC is not enabled
    on it — deliberately indistinguishable to a caller.
    
  """
  @spec config(room_id()) :: {:ok, config()} | {:error, :room_not_found}
  def config(_room_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: {:error, :room_not_found}, else: {:ok, %{topology: :star, host_user_id: Enum.random([nil, "00000000-0000-0000-0000-000000000000"]), late_join: true, reconnect_timeout: 30_000}}

      _ ->
        raise "Gamend.Signaling.config/1 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    Turns signaling on or off for a lobby, and sets how it behaves.
    
    The only writer of the `webrtc_*` columns. Options: `:enabled`, `:topology`
    (`:star` | `:mesh`), `:late_join`, `:reconnect_timeout`.
    
    Deliberately not part of the lobby changeset — a client `PATCH` must not be
    able to reach any of it. The star host is not settable at all; it is always
    the lobby host.
    
  """
  @spec configure(
  Gamend.Lobbies.Lobby.t() | room_id(),
  keyword()
) :: {:ok, Gamend.Lobbies.Lobby.t()} | {:error, term()}
  def configure(_room_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %Gamend.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "Gamend.Signaling.configure/2 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    Whether the lobby has WebRTC enabled.
  """
  @spec enabled?(room_id()) :: boolean()
  def enabled?(_room_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Signaling.enabled?/1 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    PubSub topic one peer listens on for messages addressed to it.
  """
  @spec inbox(room_id(), user_id()) :: String.t()
  def inbox(_room_id, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Signaling.inbox/2 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    The role `user_id` is connected with, or `nil`.
  """
  @spec peer_role(room_id(), user_id()) :: role() | nil
  def peer_role(_room_id, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Signaling.peer_role/2 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    Everyone currently connected to the room, as `%{user_id => role}`.
    
    The role is computed from the lobby on every read rather than read back from
    the presence meta it was tracked with. Otherwise a host change leaves the new
    host tracked as `:user` and the old one still holding `:host` until they
    happen to reconnect.
    
  """
  @spec peers(room_id()) :: %{required(user_id()) => role()}
  def peers(_room_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Signaling.peers/1 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    Sends `payload` to one peer.
    
    In a star room every exchange must involve the host; in a mesh room any pair
    may talk.
    
  """
  @spec relay(room_id(), user_id(), user_id(), message_type(), map()) ::
  :ok | {:error, :room_not_found | :user_not_found | :not_allowed}
  def relay(_room_id, _from, _to, _type, _payload) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Signaling.relay/5 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
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
  def stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Signaling.stats/0 is a stub - only available at runtime on Gamend"
    end
  end


  @doc ~S"""
    PubSub topic carrying a room's presence.
  """
  @spec topic(room_id()) :: String.t()
  def topic(_room_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Signaling.topic/1 is a stub - only available at runtime on Gamend"
    end
  end

end
