defmodule GameServer.Signaling.Server do
  @moduledoc """
  Signaling relay for WebRTC user-to-user and client-server topologies.

  Rooms are created explicitly by a worker process (e.g. a lobby worker) and
  are keyed by the lobby id. Each room stores its topology and, for :star,
  the designated host user id. The server validates membership and topology
  rules on every relay.

  Does not create PeerConnections or handle media; only routes SDP offers,
  answers, and ICE candidates between registered users in a room.

  ## Topologies

    * `:mesh` — any member may send an offer/answer/ICE to any other member.
    * `:star` — one host user (the Godot headless server) and client users.
      Clients may only signal to the host; the host may signal to any client.
      Non-host users cannot exchange messages directly.

  Each user is monitored via `Process.monitor/1`. When a user crashes or
  disconnects it enters a grace period so that reconnections keep the same
  user_id. If the grace period expires, the remaining users are notified.
  """

  use GenServer
  require Logger

  defstruct rooms: %{}, refs: %{}

  # ── Public API ───────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    if enabled?() do
      Logger.info("SignalingServer: started")
    else
      Logger.info("SignalingServer: disabled, idle")
    end

    {:ok, %__MODULE__{}}
  end

  defp enabled? do
    Application.get_env(:game_server_core, __MODULE__, [])[:enabled] != false
  end

  @doc """
  Creates a signaling room. `room_id` is typically the lobby id.

  For `:star` topology `host_user_id` is required and designates the user
  that will act as the authoritative server user.

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
  Closes a signaling room. Existing users are notified with a room_closed
  event so their channels can stop gracefully.
  """
  def close_room(room_id) do
    GenServer.call(__MODULE__, {:close_room, room_id})
  end

  def exists_room?(room_id) do
    GenServer.call(__MODULE__, {:room_exists, room_id})
  end

  @doc """
  Registers a user in a room using the authenticated `user_id`.

  Returns `{:ok, role}` where `role` is derived from the room topology and
  the provided `user_id`. Returns `{:error, :room_not_found}` if the room
  does not exist, `{:error, :not_allowed}` if the user is not in the
  allowed list and late join is disabled, and `{:ok, role}` on
  reconnection.
  """
  def join_room(room_id, user_id, pid, metadata \\ %{})
      when is_binary(room_id) and is_binary(user_id) and is_pid(pid) do
    GenServer.call(__MODULE__, {:join_room, room_id, user_id, pid, metadata})
  end

  def leave_room(room_id, user_id) when is_binary(room_id) and is_binary(user_id) do
    GenServer.call(__MODULE__, {:leave_room, room_id, user_id})
  end

  @doc """
  Allows a user to join a room after it has been created (late join).
  Called by the lobby hook when a new user joins the lobby.
  """
  def allow_user(room_id, user_id, role \\ :user) do
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
  Routes a signaling message from one user to a specific target.

  Enforces topology rules: in `:star` mode a non-host user may only relay
  to the host.
  """
  def relay_message(room_id, from_user_id, to_user_id, type, payload) do
    GenServer.call(__MODULE__, {:relay_message, room_id, from_user_id, to_user_id, type, payload})
  end

  @doc """
  Broadcasts a signaling message to every other user in the room.

  In `:star` mode only the host may broadcast.
  """
  def broadcast_message(room_id, from_user_id, type, payload) do
    GenServer.call(__MODULE__, {:broadcast_message, room_id, from_user_id, type, payload})
  end

  def list_users(room_id) do
    GenServer.call(__MODULE__, {:list_users, room_id})
  end

  def room_host?(room_id, user_id) do
    GenServer.call(__MODULE__, {:room_host, room_id, user_id})
  end

  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id})
  end

  def update_room_host(room_id, new_host_user_id) do
    GenServer.call(__MODULE__, {:update_room_host, room_id, new_host_user_id})
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────

  @impl true
  def handle_call({:create_room, room_id, topology, host_user_id, opts}, _from, state) do
    if Map.has_key?(state.rooms, room_id) do
      Logger.warning("SignalingServer: room already exists room=#{room_id}")
      {:reply, {:error, :already_exists}, state}
    else
      allowed_users = Keyword.get(opts, :allowed_users, %{})
      late_join = Keyword.get(opts, :late_join, true)
      reconnect_timeout = Keyword.get(opts, :reconnect_timeout, 30_000)

      room = %{
        topology: topology,
        host_user_id: host_user_id,
        allowed_users: allowed_users,
        users: %{},
        late_join: late_join,
        reconnect_timeout: reconnect_timeout
      }

      Logger.info(
        "SignalingServer: room created room=#{room_id} topology=#{topology} host_user_id=#{host_user_id || "none"} allowed_users=#{map_size(allowed_users)} late_join=#{late_join}"
      )

      {:reply, :ok, %{state | rooms: Map.put(state.rooms, room_id, room)}}
    end
  end

  @impl true
  def handle_call({:close_room, room_id}, _from, state) do
    case Map.pop(state.rooms, room_id) do
      {nil, _} ->
        Logger.warning("SignalingServer: close_room for non-existent room=#{room_id}")
        {:reply, {:error, :room_not_found}, state}

      {room, rooms} ->
        user_count = map_size(room.users)

        Logger.info(
          "SignalingServer: closing room=#{room_id} topology=#{room.topology} evicting=#{user_count}"
        )

        for {user_id, %{pid: pid}} <- room.users do
          Logger.debug(
            "SignalingServer: sending room_closed to user=#{user_id} pid=#{inspect(pid)}"
          )

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
        Logger.warning(
          "SignalingServer: allow_user failed room_not_found room=#{room_id} user=#{user_id}"
        )

        {:reply, {:error, :room_not_found}, state}

      room ->
        allowed_users = Map.put(room.allowed_users, user_id, role)
        room = %{room | allowed_users: allowed_users}
        rooms = Map.put(state.rooms, room_id, room)

        Logger.info("SignalingServer: allowed user room=#{room_id} user=#{user_id} role=#{role}")
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

        {_room, rooms, refs} =
          if user = Map.get(room.users, user_id) do
            if user.disconnect_timer, do: Process.cancel_timer(user.disconnect_timer)

            {user, users} = Map.pop(room.users, user_id)
            send(user.pid, {:signaling_relay, :room_closed, nil, %{reason: "removed_from_lobby"}})

            for {other_id, %{pid: other_pid}} <- users, other_id != user_id do
              send(other_pid, {:signaling_relay, :user_left, user_id, %{user_id: user_id}})
            end

            room = %{room | users: users}
            rooms = Map.put(rooms, room_id, room)

            ref_entry =
              Enum.find(state.refs, fn {_ref, {r, u}} -> r == room_id and u == user_id end)

            refs = if ref_entry, do: Map.delete(state.refs, elem(ref_entry, 0)), else: state.refs

            {room, rooms, refs}
          else
            {room, rooms, state.refs}
          end

        Logger.info("SignalingServer: disallowed user room=#{room_id} user=#{user_id}")
        {:reply, :ok, %{state | rooms: rooms, refs: refs}}
    end
  end

  @impl true
  def handle_call({:join_room, room_id, user_id, pid, metadata}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning(
          "SignalingServer: join_room failed room_not_found room=#{room_id} user=#{user_id}"
        )

        {:reply, {:error, :room_not_found}, state}

      room ->
        allowed_role = Map.get(room.allowed_users, user_id)

        cond do
          is_nil(allowed_role) and not room.late_join ->
            Logger.warning(
              "SignalingServer: join_room failed not_allowed room=#{room_id} user=#{user_id}"
            )

            {:reply, {:error, :not_allowed}, state}

          user = Map.get(room.users, user_id) ->
            # Reconnection: same user_id reconnecting before the grace period expires.
            if user.disconnect_timer, do: Process.cancel_timer(user.disconnect_timer)

            ref = Process.monitor(pid)
            user = %{user | pid: pid, ref: ref, status: :connected, disconnect_timer: nil}
            users = Map.put(room.users, user_id, user)
            room = %{room | users: users}
            rooms = Map.put(state.rooms, room_id, room)
            refs = Map.put(state.refs, ref, {room_id, user_id})

            user_count = map_size(users)

            Logger.info(
              "SignalingServer: user reconnected room=#{room_id} user=#{user_id} role=#{user.role} total_users=#{user_count}"
            )

            for {other_id, %{pid: other_pid}} <- users, other_id != user_id do
              Logger.debug(
                "SignalingServer: notifying user=#{other_id} of user_rejoined user=#{user_id}"
              )

              send(
                other_pid,
                {:signaling_relay, :user_rejoined, user_id,
                 %{
                   user_id: user_id,
                   role: user.role
                 }}
              )
            end

            {:reply, {:ok, user.role}, %{state | rooms: rooms, refs: refs}}

          true ->
            role = allowed_role || default_role(room, user_id)
            ref = Process.monitor(pid)

            user = %{
              pid: pid,
              ref: ref,
              user_id: user_id,
              role: role,
              metadata: metadata,
              status: :connected,
              joined_at: System.monotonic_time(:second),
              disconnect_timer: nil
            }

            users = Map.put(room.users, user_id, user)
            room = %{room | users: users}
            rooms = Map.put(state.rooms, room_id, room)
            refs = Map.put(state.refs, ref, {room_id, user_id})

            user_count = map_size(users)

            Logger.info(
              "SignalingServer: user joined room=#{room_id} user=#{user_id} role=#{role} total_users=#{user_count}"
            )

            # Notify existing peers about the newcomer.
            for {other_id, %{pid: other_pid}} <- users, other_id != user_id do
              Logger.debug(
                "SignalingServer: notifying user=#{other_id} of user_joined user=#{user_id}"
              )

              send(
                other_pid,
                {:signaling_relay, :user_joined, user_id, %{user_id: user_id, role: role}}
              )
            end

            # Notify the newly joined peer about existing peers so it can initiate
            # connections (e.g. star clients connecting to the host).
            for {other_id, %{role: other_role}} <- users, other_id != user_id do
              Logger.debug(
                "SignalingServer: seeding existing user to new user=#{user_id} other=#{other_id} role=#{other_role}"
              )

              send(
                pid,
                {:signaling_relay, :user_joined, other_id, %{user_id: other_id, role: other_role}}
              )
            end

            {:reply, {:ok, role}, %{state | rooms: rooms, refs: refs}}
        end
    end
  end

  @impl true
  def handle_call({:leave_room, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning(
          "SignalingServer: leave_room failed room_not_found room=#{room_id} user=#{user_id}"
        )

        {:reply, {:error, :room_not_found}, state}

      room ->
        case Map.pop(room.users, user_id) do
          {nil, _} ->
            Logger.warning(
              "SignalingServer: leave_room failed user_not_found room=#{room_id} user=#{user_id}"
            )

            {:reply, {:error, :user_not_found}, state}

          {user, users} ->
            if user.disconnect_timer, do: Process.cancel_timer(user.disconnect_timer)

            user_count = map_size(users)

            Logger.info(
              "SignalingServer: user leaving room=#{room_id} user=#{user_id} role=#{user.role} remaining_users=#{user_count}"
            )

            for {_other_id, %{pid: other_pid}} <- users do
              send(other_pid, {:signaling_relay, :user_left, user_id, %{user_id: user_id}})
            end

            room = %{room | users: users}

            rooms =
              if map_size(users) == 0 do
                Logger.info("SignalingServer: room empty, removing room=#{room_id}")
                Map.delete(state.rooms, room_id)
              else
                Map.put(state.rooms, room_id, room)
              end

            ref_entry =
              Enum.find(state.refs, fn {_ref, {r, u}} -> r == room_id and u == user_id end)

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
  def handle_call({:relay_message, room_id, from, to, type, payload}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning(
          "SignalingServer: relay_message failed room_not_found room=#{room_id} from=#{from} to=#{to} type=#{type}"
        )

        {:reply, {:error, :room_not_found}, state}

      room ->
        from_user = Map.get(room.users, from)
        to_user = Map.get(room.users, to)

        cond do
          is_nil(from_user) ->
            Logger.warning(
              "SignalingServer: relay_message failed user_not_found room=#{room_id} from=#{from} to=#{to} type=#{type}"
            )

            {:reply, {:error, :user_not_found}, state}

          is_nil(to_user) ->
            Logger.warning(
              "SignalingServer: relay_message failed user_not_found room=#{room_id} from=#{from} to=#{to} type=#{type}"
            )

            {:reply, {:error, :user_not_found}, state}

          room.topology == :star and from_user.role != :host and to_user.role != :host ->
            Logger.warning(
              "SignalingServer: relay_message failed not_allowed room=#{room_id} from=#{from} role=#{from_user.role} to=#{to} role=#{to_user.role}"
            )

            {:reply, {:error, :not_allowed}, state}

          true ->
            Logger.debug(
              "SignalingServer: relaying room=#{room_id} type=#{type} from=#{from} to=#{to}"
            )

            send(to_user.pid, {:signaling_relay, type, from, payload})
            {:reply, :ok, state}
        end
    end
  end

  @impl true
  def handle_call({:broadcast_message, room_id, from, type, payload}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning(
          "SignalingServer: broadcast_message failed room_not_found room=#{room_id} from=#{from} type=#{type}"
        )

        {:reply, {:error, :room_not_found}, state}

      room ->
        case Map.get(room.users, from) do
          nil ->
            Logger.warning(
              "SignalingServer: broadcast_message failed user_not_found room=#{room_id} from=#{from}"
            )

            {:reply, {:error, :user_not_found}, state}

          from_user ->
            if broadcast_allowed?(room, from_user) do
              broadcast_to_room(room_id, room, from, type, payload)
              {:reply, :ok, state}
            else
              Logger.warning(
                "SignalingServer: broadcast_message failed not_allowed room=#{room.topology} from=#{from} role=#{from_user.role}"
              )

              {:reply, {:error, :not_allowed}, state}
            end
        end
    end
  end

  @impl true
  def handle_call({:list_users, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        Logger.warning("SignalingServer: list_users failed room_not_found room=#{room_id}")
        {:reply, {:error, :room_not_found}, state}

      room ->
        users =
          Map.new(room.users, fn {user_id, user} ->
            {user_id, %{user_id: user.user_id, role: user.role, metadata: user.metadata}}
          end)

        {:reply, users, state}
    end
  end

  def handle_call({:room_host, room_id, user_id}, _from, state) do
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
          Logger.info("SignalingServer: updated host room=#{room_id} host=#{new_host_user_id}")
          {:reply, :ok, %{state | rooms: rooms}}
        end
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _} ->
        Logger.debug(
          "SignalingServer: DOWN from unknown pid=#{inspect(pid)} reason=#{inspect(reason)}"
        )

        {:noreply, state}

      {{room_id, user_id}, refs} ->
        case Map.get(state.rooms, room_id) do
          nil ->
            Logger.warning(
              "SignalingServer: DOWN for removed room room=#{room_id} user=#{user_id} pid=#{inspect(pid)} reason=#{inspect(reason)}"
            )

            {:noreply, %{state | refs: refs}}

          room ->
            user = Map.get(room.users, user_id)

            if user do
              # Start grace period instead of removing immediately so the same
              # user_id can reconnect and keep its role.
              timer =
                Process.send_after(
                  self(),
                  {:reconnect_timeout, room_id, user_id},
                  room.reconnect_timeout
                )

              user = %{user | status: :disconnected, disconnect_timer: timer}
              users = Map.put(room.users, user_id, user)
              room = %{room | users: users}
              rooms = Map.put(state.rooms, room_id, room)

              Logger.info(
                "SignalingServer: user disconnected room=#{room_id} user=#{user_id} grace=#{room.reconnect_timeout}ms pid=#{inspect(pid)} reason=#{inspect(reason)}"
              )

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
        user = Map.get(room.users, user_id)

        if user && user.status == :disconnected do
          {_user, users} = Map.pop(room.users, user_id)
          remaining = map_size(users)

          Logger.info(
            "SignalingServer: reconnect timeout expired room=#{room_id} user=#{user_id} remaining_users=#{remaining}"
          )

          for {other_id, %{pid: other_pid}} <- users, other_id != user_id do
            send(other_pid, {:signaling_relay, :user_left, user_id, %{user_id: user_id}})
          end

          rooms =
            if map_size(users) == 0 do
              Logger.info("SignalingServer: room empty after timeout, removing room=#{room_id}")
              Map.delete(state.rooms, room_id)
            else
              Map.put(state.rooms, room_id, %{room | users: users})
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
      :mesh -> :user
      :star -> if user_id == room.host_user_id, do: :host, else: :client
    end
  end

  defp broadcast_allowed?(room, from_user) do
    room.topology != :star or from_user.role == :host
  end

  defp broadcast_to_room(room_id, room, from, type, payload) do
    targets =
      Enum.filter(room.users, fn {user_id, _} -> user_id != from end)
      |> Enum.map(fn {id, _} -> id end)

    Logger.debug(
      "SignalingServer: broadcasting room=#{room_id} type=#{type} from=#{from} targets=#{length(targets)}"
    )

    for {user_id, %{pid: pid}} <- room.users, user_id != from do
      send(pid, {:signaling_relay, type, from, payload})
    end

    :ok
  end
end
