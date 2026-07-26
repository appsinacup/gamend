defmodule GameServerWeb.SignalingBroker do
  @moduledoc """
  Signaling relay for WebRTC peer-to-peer and client-server topologies.

  Rooms are created explicitly by a worker process (e.g. a lobby worker) and
  are keyed by the lobby id. Each room stores its topology and, for :star,
  the designated host user id. The broker validates membership and topology
  rules on every relay.

  Does not create PeerConnections or handle media; only routes SDP offers,
  answers, and ICE candidates between registered peers in a room.

  ## Topologies

    * `:mesh` — any member may send an offer/answer/ICE to any other member.
    * `:star` — one host peer (the Godot headless server) and client peers.
      Clients may only signal to the host; the host may signal to any client.
      Non-host peers cannot exchange messages directly.

  Each peer is monitored via `Process.monitor/1`. When a peer crashes or
  disconnects it enters a grace period so that reconnections keep the same
  user_id. If the grace period expires, the remaining peers are notified.
  """

  use GenServer
  require Logger

  defstruct rooms: %{}, refs: %{}

  # ── Public API ───────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates a signaling room. `room_id` is typically the lobby id.

  For `:star` topology `host_user_id` is required and designates the user
  that will act as the authoritative server peer.

  `allowed_users` is a map of `user_id => role` populated by the lobby hook.
  `late_join` controls whether users not in the initial list may join later.
  `reconnect_timeout` is the grace period in milliseconds before a
  disconnected user is removed.
  """
  def create_room(room_id, topology, opts \\ []) when topology in [:mesh, :star] do
    host_user_id = if topology == :star, do: Keyword.fetch!(opts, :host_user_id), else: nil
    GenServer.call(__MODULE__, {:create_room, room_id, topology, host_user_id, opts})
  end

  @doc """
  Closes a signaling room. Existing peers are notified with a `room_closed`
  event so their channels can stop gracefully.
  """
  def close_room(room_id) do
    GenServer.call(__MODULE__, {:close_room, room_id})
  end

  def room_exists?(room_id) do
    GenServer.call(__MODULE__, {:room_exists, room_id})
  end

  @doc """
  Registers a peer in a room using the authenticated `user_id`.

  Returns `{:ok, role}` where `role` is derived from the room topology and
  the provided `user_id`. Returns `{:error, :room_not_found}` if the room
  does not exist, `{:error, :not_allowed}` if the user is not in the
  allowed list and late join is disabled, and `{:ok, role}` on
  reconnection.
  """
  def join(room_id, user_id, pid, metadata \\ %{})
      when is_binary(room_id) and is_binary(user_id) and is_pid(pid) do
    GenServer.call(__MODULE__, {:join, room_id, user_id, pid, metadata})
  end

  def leave(room_id, user_id) when is_binary(room_id) and is_binary(user_id) do
    GenServer.call(__MODULE__, {:leave, room_id, user_id})
  end

  @doc """
  Allows a user to join a room after it has been created (late join).
  Called by the lobby hook when a new user joins the lobby.
  """
  def allow_user(room_id, user_id, role \\ :peer) do
    GenServer.call(__MODULE__, {:allow_user, room_id, user_id, role})
  end

  @doc """
  Removes a user from the allowed list and kicks them if connected.
  Called by the lobby hook when a user leaves the lobby.
  """
  def disallow_user(room_id, user_id) do
    GenServer.call(__MODULE__, {:disallow_user, room_id, user_id})
  end

  @doc """
  Routes a signaling message from one peer to a specific target.

  Enforces topology rules: in `:star` mode a non-host peer may only relay
  to the host.
  """
  def relay(room_id, from_user_id, to_user_id, type, payload) do
    GenServer.call(__MODULE__, {:relay, room_id, from_user_id, to_user_id, type, payload})
  end

  @doc """
  Broadcasts a signaling message to every other peer in the room.

  In `:star` mode only the host may broadcast.
  """
  def broadcast(room_id, from_user_id, type, payload) do
    GenServer.call(__MODULE__, {:broadcast, room_id, from_user_id, type, payload})
  end

  def list_peers(room_id) do
    GenServer.call(__MODULE__, {:list_peers, room_id})
  end

  def is_host?(room_id, user_id) do
    GenServer.call(__MODULE__, {:is_host, room_id, user_id})
  end

  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id})
  end

  def update_room_host(room_id, new_host_user_id) do
    GenServer.call(__MODULE__, {:update_room_host, room_id, new_host_user_id})
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:create_room, room_id, topology, host_user_id, opts}, _from, state) do
    if Map.has_key?(state.rooms, room_id) do
      Logger.warning("SignalingBroker: room already exists room=#{room_id}")
      {:reply, {:error, :already_exists}, state}
    else
      allowed_users = Keyword.get(opts, :allowed_users, %{})
      late_join = Keyword.get(opts, :late_join, true)
      reconnect_timeout = Keyword.get(opts, :reconnect_timeout, 30_000)

      room = %{
        topology: topology,
        host_user_id: host_user_id,
        allowed_users: allowed_users,
        peers: %{},
        late_join: late_join,
        reconnect_timeout: reconnect_timeout
      }

      Logger.info("SignalingBroker: room created room=#{room_id} topology=#{topology} host_user_id=#{host_user_id || "none"} allowed_users=#{map_size(allowed_users)} late_join=#{late_join}")
      {:reply, :ok, %{state | rooms: Map.put(state.rooms, room_id, room)}}
    end
  end

  @impl true
  def handle_call({:close_room, room_id}, _from, state) do
    case Map.pop(state.rooms, room_id) do
      {nil, _} ->
        Logger.warning("SignalingBroker: close_room for non-existent room=#{room_id}")
        {:reply, {:error, :room_not_found}, state}

      {room, rooms} ->
        peer_count = map_size(room.peers)
        Logger.info("SignalingBroker: closing room=#{room_id} topology=#{room.topology} evicting=#{peer_count}")

        for {user_id, %{pid: pid}} <- room.peers do
          Logger.debug("SignalingBroker: sending room_closed to user=#{user_id} pid=#{inspect(pid)}")
          send(pid, {:signaling_relay, :room_closed, nil, %{}})
        end

        refs = Enum.reject(state.refs, fn {_ref, {r, _u}} -> r == room_id end) |> Map.new()

        {:reply, :ok, %{state | rooms: rooms, refs: refs}}
    end
  end

  @impl true
  def handle_call({:room_exists, room_id}, _from, state) do
    {:reply, Map.has_key?(state.rooms, room_id), state}
  end

  @impl true
  def handle_call({:allow_user, room_id, user_id, role}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning("SignalingBroker: allow_user failed room_not_found room=#{room_id} user=#{user_id}")
        {:reply, {:error, :room_not_found}, state}

      room ->
        allowed_users = Map.put(room.allowed_users, user_id, role)
        room = %{room | allowed_users: allowed_users}
        rooms = Map.put(state.rooms, room_id, room)

        Logger.info("SignalingBroker: allowed user room=#{room_id} user=#{user_id} role=#{role}")
        {:reply, :ok, %{state | rooms: rooms}}
    end
  end

  @impl true
  def handle_call({:disallow_user, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :room_not_found}, state}

      room ->
        allowed_users = Map.delete(room.allowed_users, user_id)
        room = %{room | allowed_users: allowed_users}
        rooms = Map.put(state.rooms, room_id, room)

        {room, rooms, refs} =
          if peer = Map.get(room.peers, user_id) do
            if peer.disconnect_timer, do: Process.cancel_timer(peer.disconnect_timer)

            {peer, peers} = Map.pop(room.peers, user_id)
            send(peer.pid, {:signaling_relay, :room_closed, nil, %{reason: "removed_from_lobby"}})

            for {other_id, %{pid: other_pid}} <- peers, other_id != user_id do
              send(other_pid, {:signaling_relay, :peer_left, user_id, %{user_id: user_id}})
            end

            room = %{room | peers: peers}
            rooms = Map.put(rooms, room_id, room)

            ref_entry = Enum.find(state.refs, fn {_ref, {r, u}} -> r == room_id and u == user_id end)
            refs = if ref_entry, do: Map.delete(state.refs, elem(ref_entry, 0)), else: state.refs

            {room, rooms, refs}
          else
            {room, rooms, state.refs}
          end

        Logger.info("SignalingBroker: disallowed user room=#{room_id} user=#{user_id}")
        {:reply, :ok, %{state | rooms: rooms, refs: refs}}
    end
  end

  @impl true
  def handle_call({:join, room_id, user_id, pid, metadata}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning("SignalingBroker: join failed room_not_found room=#{room_id} user=#{user_id}")
        {:reply, {:error, :room_not_found}, state}

      room ->
        allowed_role = Map.get(room.allowed_users, user_id)

        cond do
          is_nil(allowed_role) and not room.late_join ->
            Logger.warning("SignalingBroker: join failed not_allowed room=#{room_id} user=#{user_id}")
            {:reply, {:error, :not_allowed}, state}

          peer = Map.get(room.peers, user_id) ->
            # Reconnection: same user_id reconnecting before the grace period expires.
            if peer.disconnect_timer, do: Process.cancel_timer(peer.disconnect_timer)

            ref = Process.monitor(pid)
            peer = %{peer | pid: pid, ref: ref, status: :connected, disconnect_timer: nil}
            peers = Map.put(room.peers, user_id, peer)
            room = %{room | peers: peers}
            rooms = Map.put(state.rooms, room_id, room)
            refs = Map.put(state.refs, ref, {room_id, user_id})

            peer_count = map_size(peers)
            Logger.info("SignalingBroker: user reconnected room=#{room_id} user=#{user_id} role=#{peer.role} total_peers=#{peer_count}")

            for {other_id, %{pid: other_pid}} <- peers, other_id != user_id do
              Logger.debug("SignalingBroker: notifying user=#{other_id} of peer_rejoined user=#{user_id}")
              send(other_pid, {:signaling_relay, :peer_rejoined, user_id, %{
                user_id: user_id,
                role: peer.role
              }})
            end

            {:reply, {:ok, peer.role}, %{state | rooms: rooms, refs: refs}}

          true ->
            role = allowed_role || default_role(room, user_id)
            ref = Process.monitor(pid)

            peer = %{
              pid: pid,
              ref: ref,
              user_id: user_id,
              role: role,
              metadata: metadata,
              status: :connected,
              joined_at: System.monotonic_time(:second),
              disconnect_timer: nil
            }

            peers = Map.put(room.peers, user_id, peer)
            room = %{room | peers: peers}
            rooms = Map.put(state.rooms, room_id, room)
            refs = Map.put(state.refs, ref, {room_id, user_id})

            peer_count = map_size(peers)
            Logger.info("SignalingBroker: user joined room=#{room_id} user=#{user_id} role=#{role} total_peers=#{peer_count}")

            # Notify existing peers about the newcomer.
            for {other_id, %{pid: other_pid}} <- peers, other_id != user_id do
              Logger.debug("SignalingBroker: notifying user=#{other_id} of peer_joined user=#{user_id}")
              send(other_pid, {:signaling_relay, :peer_joined, user_id, %{
                user_id: user_id,
                role: role
              }})
            end

            # Notify the newly joined peer about existing peers so it can initiate
            # connections (e.g. star clients connecting to the host).
            for {other_id, %{role: other_role}} <- peers, other_id != user_id do
              Logger.debug("SignalingBroker: seeding existing peer to new user=#{user_id} other=#{other_id} role=#{other_role}")
              send(pid, {:signaling_relay, :peer_joined, other_id, %{
                user_id: other_id,
                role: other_role
              }})
            end

            {:reply, {:ok, role}, %{state | rooms: rooms, refs: refs}}
        end
    end
  end

  @impl true
  def handle_call({:leave, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning("SignalingBroker: leave failed room_not_found room=#{room_id} user=#{user_id}")
        {:reply, {:error, :room_not_found}, state}

      room ->
        case Map.pop(room.peers, user_id) do
          {nil, _} ->
            Logger.warning("SignalingBroker: leave failed peer_not_found room=#{room_id} user=#{user_id}")
            {:reply, {:error, :peer_not_found}, state}

          {peer, peers} ->
            if peer.disconnect_timer, do: Process.cancel_timer(peer.disconnect_timer)

            peer_count = map_size(peers)
            Logger.info("SignalingBroker: user leaving room=#{room_id} user=#{user_id} role=#{peer.role} remaining_peers=#{peer_count}")

            for {other_id, %{pid: other_pid}} <- peers do
              send(other_pid, {:signaling_relay, :peer_left, user_id, %{user_id: user_id}})
            end

            room = %{room | peers: peers}

            rooms =
              if map_size(peers) == 0 do
                Logger.info("SignalingBroker: room empty, removing room=#{room_id}")
                Map.delete(state.rooms, room_id)
              else
                Map.put(state.rooms, room_id, room)
              end

            ref_entry = Enum.find(state.refs, fn {_ref, {r, u}} -> r == room_id and u == user_id end)

            refs =
              if ref_entry do
                Map.delete(state.refs, elem(ref_entry, 0))
              else
                state.refs
              end

            {:reply, :ok, %{state | rooms: rooms, refs: refs}}
        end
    end
  end

  @impl true
  def handle_call({:relay, room_id, from, to, type, payload}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning("SignalingBroker: relay failed room_not_found room=#{room_id} from=#{from} to=#{to} type=#{type}")
        {:reply, {:error, :room_not_found}, state}

      room ->
        from_peer = Map.get(room.peers, from)
        to_peer = Map.get(room.peers, to)

        cond do
          is_nil(from_peer) ->
            Logger.warning("SignalingBroker: relay failed peer_not_found room=#{room_id} from=#{from} to=#{to} type=#{type}")
            {:reply, {:error, :peer_not_found}, state}

          is_nil(to_peer) ->
            Logger.warning("SignalingBroker: relay failed peer_not_found room=#{room_id} from=#{from} to=#{to} type=#{type}")
            {:reply, {:error, :peer_not_found}, state}

          room.topology == :star and from_peer.role != :host and to_peer.role != :host ->
            Logger.warning("SignalingBroker: relay failed not_allowed room=#{room_id} from=#{from} role=#{from_peer.role} to=#{to} role=#{to_peer.role}")
            {:reply, {:error, :not_allowed}, state}

          true ->
            Logger.debug("SignalingBroker: relaying room=#{room_id} type=#{type} from=#{from} to=#{to}")
            send(to_peer.pid, {:signaling_relay, type, from, payload})
            {:reply, :ok, state}
        end
    end
  end

  @impl true
  def handle_call({:broadcast, room_id, from, type, payload}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning("SignalingBroker: broadcast failed room_not_found room=#{room_id} from=#{from} type=#{type}")
        {:reply, {:error, :room_not_found}, state}

      room ->
        from_peer = Map.get(room.peers, from)

        if is_nil(from_peer) do
          Logger.warning("SignalingBroker: broadcast failed peer_not_found room=#{room_id} from=#{from}")
          {:reply, {:error, :peer_not_found}, state}
        else
          if room.topology == :star and from_peer.role != :host do
            Logger.warning("SignalingBroker: broadcast failed not_allowed room=#{room_id} from=#{from} role=#{from_peer.role}")
            {:reply, {:error, :not_allowed}, state}
          else
            targets = Enum.filter(room.peers, fn {user_id, _} -> user_id != from end) |> Enum.map(fn {id, _} -> id end)
            Logger.debug("SignalingBroker: broadcasting room=#{room_id} type=#{type} from=#{from} targets=#{length(targets)}")

            for {user_id, %{pid: pid}} <- room.peers, user_id != from do
              send(pid, {:signaling_relay, type, from, payload})
            end

            {:reply, :ok, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:list_peers, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning("SignalingBroker: list_peers failed room_not_found room=#{room_id}")
        {:reply, {:error, :room_not_found}, state}

      room ->
        peers =
          Map.new(room.peers, fn {user_id, peer} ->
            {user_id, %{user_id: peer.user_id, role: peer.role, metadata: peer.metadata}}
          end)

        {:reply, peers, state}
    end
  end

  def handle_call({:is_host, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, false, state}

      room ->
        {:reply, room.host_user_id == user_id, state}
    end
  end

  def handle_call({:get_room, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :room_not_found}, state}

      room ->
        {:reply, {:ok, %{topology: room.topology, host_user_id: room.host_user_id}}, state}
    end
  end

  def handle_call({:update_room_host, room_id, new_host_user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :room_not_found}, state}

      room ->
        if room.topology != :star do
          {:reply, {:error, :not_star}, state}
        else
          room = %{room | host_user_id: new_host_user_id}
          rooms = Map.put(state.rooms, room_id, room)
          Logger.info("SignalingBroker: updated host room=#{room_id} host=#{new_host_user_id}")
          {:reply, :ok, %{state | rooms: rooms}}
        end
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _} ->
        Logger.debug("SignalingBroker: DOWN from unknown pid=#{inspect(pid)} reason=#{inspect(reason)}")
        {:noreply, state}

      {{room_id, user_id}, refs} ->
        case Map.get(state.rooms, room_id) do
          nil ->
            Logger.warning("SignalingBroker: DOWN for removed room room=#{room_id} user=#{user_id} pid=#{inspect(pid)} reason=#{inspect(reason)}")
            {:noreply, %{state | refs: refs}}

          room ->
            peer = Map.get(room.peers, user_id)

            if peer do
              # Start grace period instead of removing immediately so the same
              # user_id can reconnect and keep its role.
              timer = Process.send_after(self(), {:reconnect_timeout, room_id, user_id}, room.reconnect_timeout)
              peer = %{peer | status: :disconnected, disconnect_timer: timer}
              peers = Map.put(room.peers, user_id, peer)
              room = %{room | peers: peers}
              rooms = Map.put(state.rooms, room_id, room)

              Logger.info("SignalingBroker: user disconnected room=#{room_id} user=#{user_id} grace=#{room.reconnect_timeout}ms pid=#{inspect(pid)} reason=#{inspect(reason)}")
              {:noreply, %{state | rooms: rooms, refs: refs}}
            else
              {:noreply, %{state | refs: refs}}
            end
        end
    end
  end

  @impl true
  def handle_info({:reconnect_timeout, room_id, user_id}, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:noreply, state}

      room ->
        peer = Map.get(room.peers, user_id)

        if peer && peer.status == :disconnected do
          {_peer, peers} = Map.pop(room.peers, user_id)
          remaining = map_size(peers)
          Logger.info("SignalingBroker: reconnect timeout expired room=#{room_id} user=#{user_id} remaining_peers=#{remaining}")

          for {other_id, %{pid: other_pid}} <- peers, other_id != user_id do
            send(other_pid, {:signaling_relay, :peer_left, user_id, %{user_id: user_id}})
          end

          rooms =
            if map_size(peers) == 0 do
              Logger.info("SignalingBroker: room empty after timeout, removing room=#{room_id}")
              Map.delete(state.rooms, room_id)
            else
              Map.put(state.rooms, room_id, %{room | peers: peers})
            end

          {:noreply, %{state | rooms: rooms}}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  defp default_role(room, user_id) do
    case room.topology do
      :mesh -> :peer
      :star -> if user_id == room.host_user_id, do: :host, else: :client
    end
  end
end
