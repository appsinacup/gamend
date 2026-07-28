defmodule GameServerWeb.SignalingChannel do
  @moduledoc """
  Channel for WebRTC signaling relay.

  Topic: `signaling:<room_id>`

  Rooms are created by the `WebRTCLobbyHook` through `Server.create_room/3`.
  The allowed-user list is populated by the hook, so this channel does not
  need to query the lobby system. The topology and host are fixed at room
  creation; clients cannot choose their role.

  ## Lifecycle

  On join the authenticated `user_id` is used directly as the user identity.
  The server assigns the role (`:host` or `:client` for `:star`, `:user` for
  `:mesh`) based on the room's configuration. If the same user_id reconnects
  within the configured grace period, the existing user is preserved and a
  `user_rejoined` event is broadcast.

  ## Messages

  Inbound events (from client):

      push("offer", %{target: "user-uuid", sdp: "..."})
      push("answer", %{target: "user-uuid", sdp: "..."})
      push("ice", %{target: "user-uuid", candidate: "..."})
      push("broadcast_offer", %{sdp: "..."})

  Outbound events (to client):

      "offer"         — %{sdp: "...", from_user_id: "..."}
      "answer"        — %{sdp: "...", from_user_id: "..."}
      "ice"           — %{candidate: "...", from_user_id: "..."}
      "user_joined"   — %{user_id: "...", role: :host | :client | :user}
      "user_rejoined" — %{user_id: "...", role: :host | :client | :user}
      "user_left"     — %{user_id: "..."}
      "room_closed"   — %{}
  """

  use Phoenix.Channel

  import GameServerWeb.ChannelPush
  require Logger

  alias GameServer.Signaling.Server

  # WebSocket message rate limits (per user) — defaults, overridden by config
  @default_ws_rate_limit 300
  @default_ws_rate_window :timer.seconds(10)

  # Separate ICE candidate budget — prevents ICE flooding from starving
  # other channel events. A typical WebRTC session sends 5–30 candidates.
  @default_ice_rate_limit 150
  @default_ice_rate_window :timer.seconds(30)

  @impl true
  def join("signaling:" <> room_id, _payload, socket) do
    user_id = socket.assigns.current_scope.user_id

    if is_nil(user_id) do
      Logger.warning(
        "SignalingChannel: unauthorized join attempt room=#{room_id} missing user_id"
      )

      {:error, %{reason: "unauthorized"}}
    else
      case Server.join_room(room_id, user_id, self(), %{}) do
        {:ok, role} ->
          Logger.info("SignalingChannel: join ok room=#{room_id} user=#{user_id} role=#{role}")

          {:ok, %{user_id: user_id, role: role},
           assign(socket,
             signaling_room: room_id,
             signaling_user_id: user_id,
             signaling_role: role
           )}

        {:error, :room_not_found} ->
          Logger.warning(
            "SignalingChannel: join failed room_not_found room=#{room_id} user=#{user_id}"
          )

          {:error, %{reason: "room_not_found"}}

        {:error, :not_allowed} ->
          Logger.warning(
            "SignalingChannel: join failed not_allowed room=#{room_id} user=#{user_id}"
          )

          {:error, %{reason: "not_allowed"}}

        {:error, reason} ->
          Logger.warning(
            "SignalingChannel: join failed reason=#{reason} room=#{room_id} user=#{user_id}"
          )

          {:error, %{reason: to_string(reason)}}
      end
    end
  end

  # ── Signaling relay ──────────────────────────────────────────────────────

  @impl true
  def handle_in("offer", %{"target" => target, "sdp" => sdp}, socket) do
    with :ok <- check_ws_rate_limit(socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Server.relay_message(room, from, target, :offer, %{sdp: sdp}) do
        :ok ->
          {:reply, {:ok, %{}}, socket}

        {:error, :user_not_found} ->
          Logger.warning(
            "SignalingChannel: offer failed user_not_found room=#{room} from=#{from} target=#{target}"
          )

          {:reply, {:error, %{error: "user_not_found"}}, socket}

        {:error, :not_allowed} ->
          Logger.warning(
            "SignalingChannel: offer failed not_allowed room=#{room} from=#{from} target=#{target}"
          )

          {:reply, {:error, %{error: "not_allowed"}}, socket}

        {:error, :room_not_found} ->
          Logger.warning(
            "SignalingChannel: offer failed room_not_found room=#{room} from=#{from}"
          )

          {:stop, :normal, {:error, %{error: "room_not_found"}}, socket}
      end
    end
  end

  @impl true
  def handle_in("answer", %{"target" => target, "sdp" => sdp}, socket) do
    with :ok <- check_ws_rate_limit(socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Server.relay_message(room, from, target, :answer, %{sdp: sdp}) do
        :ok ->
          {:reply, {:ok, %{}}, socket}

        {:error, :user_not_found} ->
          Logger.warning(
            "SignalingChannel: answer failed user_not_found room=#{room} from=#{from} target=#{target}"
          )

          {:reply, {:error, %{error: "user_not_found"}}, socket}

        {:error, :not_allowed} ->
          Logger.warning(
            "SignalingChannel: answer failed not_allowed room=#{room} from=#{from} target=#{target}"
          )

          {:reply, {:error, %{error: "not_allowed"}}, socket}

        {:error, :room_not_found} ->
          Logger.warning(
            "SignalingChannel: answer failed room_not_found room=#{room} from=#{from}"
          )

          {:stop, :normal, {:error, %{error: "room_not_found"}}, socket}
      end
    end
  end

  @impl true
  def handle_in("ice", %{"target" => target, "candidate" => candidate}, socket) do
    with :ok <- check_ice_rate_limit(socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Server.relay_message(room, from, target, :ice, %{candidate: candidate}) do
        :ok ->
          {:reply, {:ok, %{}}, socket}

        {:error, :user_not_found} ->
          Logger.warning(
            "SignalingChannel: ice failed user_not_found room=#{room} from=#{from} target=#{target}"
          )

          {:reply, {:error, %{error: "user_not_found"}}, socket}

        {:error, :not_allowed} ->
          Logger.warning(
            "SignalingChannel: ice failed not_allowed room=#{room} from=#{from} target=#{target}"
          )

          {:reply, {:error, %{error: "not_allowed"}}, socket}

        {:error, :room_not_found} ->
          Logger.warning("SignalingChannel: ice failed room_not_found room=#{room} from=#{from}")
          {:stop, :normal, {:error, %{error: "room_not_found"}}, socket}
      end
    end
  end

  @impl true
  def handle_in("broadcast_offer", %{"sdp" => sdp}, socket) do
    with :ok <- check_ws_rate_limit(socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Server.broadcast_message(room, from, :offer, %{sdp: sdp, from_user_id: from}) do
        :ok ->
          {:reply, {:ok, %{}}, socket}

        {:error, :not_allowed} ->
          Logger.warning(
            "SignalingChannel: broadcast_offer failed not_allowed room=#{room} from=#{from}"
          )

          {:reply, {:error, %{error: "not_allowed"}}, socket}

        {:error, :room_not_found} ->
          Logger.warning(
            "SignalingChannel: broadcast_offer failed room_not_found room=#{room} from=#{from}"
          )

          {:stop, :normal, {:error, %{error: "room_not_found"}}, socket}
      end
    end
  end

  @impl true
  def handle_in("list_users", _payload, socket) do
    with :ok <- check_ws_rate_limit(socket) do
      room = socket.assigns.signaling_room

      case Server.list_users(room) do
        users when is_map(users) ->
          {:reply, {:ok, %{users: users}}, socket}

        {:error, :room_not_found} ->
          Logger.warning("SignalingChannel: list_users failed room_not_found room=#{room}")
          {:stop, :normal, {:error, %{error: "room_not_found"}}, socket}
      end
    end
  end

  @impl true
  def handle_in(event, _payload, socket) do
    Logger.warning(
      "SignalingChannel: unknown event=#{event} room=#{socket.assigns[:signaling_room] || "nil"} user=#{socket.assigns[:signaling_user_id] || "nil"}"
    )

    {:reply, {:error, %{error: "unknown_event"}}, socket}
  end

  # ── Server relay messages ────────────────────────────────────────────────

  @impl true
  def handle_info({:signaling_relay, :room_closed, nil, payload}, socket) do
    Logger.info(
      "SignalingChannel: room_closed received, stopping room=#{socket.assigns.signaling_room} user=#{socket.assigns.signaling_user_id}"
    )

    push_event(socket, "room_closed", payload)
    {:stop, :normal, socket}
  end

  @impl true
  def handle_info({:signaling_relay, type, from_user_id, payload}, socket) do
    event_name = relay_event_name(type)

    payload =
      if is_nil(from_user_id), do: payload, else: Map.put(payload, :from_user_id, from_user_id)

    push_event(socket, event_name, payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:channel_updates_flush, _}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug(
      "SignalingChannel: unexpected msg=#{inspect(msg)} room=#{socket.assigns[:signaling_room] || "nil"} user=#{socket.assigns[:signaling_user_id] || "nil"}"
    )

    {:noreply, socket}
  end

  @impl true
  def terminate(reason, socket) do
    room_id = socket.assigns[:signaling_room]
    user_id = socket.assigns[:signaling_user_id]

    if room_id && user_id do
      Logger.info(
        "SignalingChannel: terminating reason=#{inspect(reason)} room=#{room_id} user=#{user_id}"
      )

      # Do NOT call Server.leave here. The server's DOWN handler
      # starts a grace period so the same user_id can reconnect and keep
      # its role. Explicit leave is only used for intentional removal.
    else
      Logger.debug("SignalingChannel: terminating without room/user reason=#{inspect(reason)}")
    end

    :ok
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp relay_event_name(:offer), do: "offer"
  defp relay_event_name(:answer), do: "answer"
  defp relay_event_name(:ice), do: "ice"
  defp relay_event_name(:user_joined), do: "user_joined"
  defp relay_event_name(:user_rejoined), do: "user_rejoined"
  defp relay_event_name(:user_left), do: "user_left"
  defp relay_event_name(:room_closed), do: "room_closed"

  # ── WebSocket rate limiting ─────────────────────────────────────────────

  defp check_ws_rate_limit(socket) do
    config = Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, [])

    if Keyword.get(config, :enabled, true) do
      user_id = socket.assigns.current_scope.user_id
      limit = Keyword.get(config, :signaling_ws_limit, @default_ws_rate_limit)
      window = Keyword.get(config, :signaling_ws_window, @default_ws_rate_window)

      case GameServerWeb.RateLimit.hit("signaling_ws:#{user_id}", window, limit) do
        {:allow, _count} ->
          :ok

        {:deny, _retry_after} ->
          Logger.warning(
            "SignalingChannel: rate limit exceeded user=#{user_id} room=#{socket.assigns[:signaling_room] || "nil"}"
          )

          {:stop, :normal, {:error, %{error: "rate_limited"}}, socket}
      end
    else
      :ok
    end
  end

  defp check_ice_rate_limit(socket) do
    config = Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, [])

    if Keyword.get(config, :enabled, true) do
      user_id = socket.assigns.current_scope.user_id
      limit = Keyword.get(config, :signaling_ice_limit, @default_ice_rate_limit)
      window = Keyword.get(config, :signaling_ice_window, @default_ice_rate_window)

      case GameServerWeb.RateLimit.hit("signaling_ice:#{user_id}", window, limit) do
        {:allow, _count} ->
          :ok

        {:deny, _retry_after} ->
          Logger.warning(
            "SignalingChannel: ICE rate limit exceeded user=#{user_id} room=#{socket.assigns[:signaling_room] || "nil"}"
          )

          {:reply, {:error, %{error: "ice_rate_limited"}}, socket}
      end
    else
      :ok
    end
  end
end
