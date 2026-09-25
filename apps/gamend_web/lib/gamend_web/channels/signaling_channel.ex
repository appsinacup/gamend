defmodule GamendWeb.SignalingChannel do
  @moduledoc """
  Channel for WebRTC signaling relay.

  Topic: `signaling:<room_id>`

  A room is a lobby: `Gamend.Signaling` derives everything from the lobby's
  server-owned `webrtc_*` columns, so this channel keeps no membership list of
  its own and nothing here can drift from the lobby.

  ## Lifecycle

  On join the authenticated `user_id` is used directly as the user identity, and
  `Signaling.authorize/2` decides both whether the join is allowed and which
  role it gets — `:host` or `:user`. Clients cannot ask for a role. In a `:star`
  room the host is `lobby.webrtc_host_id`, or `lobby.host_id` when that is
  unset; a `:mesh` room has no host.

  If the same user_id reconnects within the configured grace period, the
  existing user is preserved and a `user_rejoined` event is broadcast.

  ## Messages

  Inbound events (from client):

      push("offer", %{target: "user-uuid", sdp: "..."})
      push("answer", %{target: "user-uuid", sdp: "..."})
      push("ice", %{target: "user-uuid", candidate: "..."})
      push("broadcast_offer", %{sdp: "..."})   # star host only
      push("list_users", %{})

  Outbound events (to client):

      "offer"         — %{sdp: "...", from_user_id: "..."}
      "answer"        — %{sdp: "...", from_user_id: "..."}
      "ice"           — %{candidate: "...", from_user_id: "..."}
      "user_joined"   — %{user_id: "...", role: :host | :user}
      "user_rejoined" — %{user_id: "...", role: :host | :user}
      "user_left"     — %{user_id: "..."}
      "room_closed"   — %{}
  """

  use Phoenix.Channel

  intercept ["presence_diff"]

  import GamendWeb.ChannelPush
  require Logger

  alias Gamend.Presence
  alias Gamend.Signaling
  alias GamendWeb.ChannelEvents

  # Per-user message and ICE budgets are the `signaling_*` settings on
  # GamendWeb.Plugs.RateLimiter. ICE has its own so a flood of candidates cannot
  # starve other channel events; a typical WebRTC session sends 5–30.

  @impl true
  def join("signaling:" <> room_id, _payload, socket) do
    user_id = socket.assigns.current_scope.user_id

    if is_nil(user_id) do
      Logger.warning(
        "SignalingChannel: unauthorized join attempt room=#{room_id} missing user_id"
      )

      {:error, %{reason: "unauthorized"}}
    else
      case Signaling.authorize(room_id, user_id) do
        {:ok, role} ->
          Logger.info("SignalingChannel: join ok room=#{room_id} user=#{user_id} role=#{role}")

          send(self(), :after_signaling_join)

          {:ok, %{user_id: user_id, role: role},
           assign(socket,
             signaling_room: room_id,
             signaling_user_id: user_id,
             signaling_role: role,
             # Read once, at join. `handle_out` for a presence diff runs in
             # *every* subscribed channel process, and `schedule_leaves/2` read
             # this from the lobby each time — so one peer leaving a 50-peer
             # room cost 50 lobby reads, each of them two multilevel cache
             # lookups (the cache key is itself a cached version counter), and
             # 50 more when the confirm timers fired.
             #
             # A room's reconnect timeout changing mid-session is a config edit,
             # and the stale value only widens or narrows a grace period, so
             # picking it up on the next join is good enough.
             signaling_reconnect_timeout: reconnect_timeout(room_id),
             pending_leaves: %{}
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
      end
    end
  end

  # ── Signaling relay ──────────────────────────────────────────────────────

  @impl true
  def handle_in("offer", %{"target" => target, "sdp" => sdp}, socket) do
    with :ok <- check_ws_rate_limit(socket),
         :ok <- validate_signal_payload(sdp, socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Signaling.relay(room, from, target, :offer, %{sdp: sdp}) do
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
    with :ok <- check_ws_rate_limit(socket),
         :ok <- validate_signal_payload(sdp, socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Signaling.relay(room, from, target, :answer, %{sdp: sdp}) do
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
    with :ok <- check_ice_rate_limit(socket),
         :ok <- validate_signal_payload(candidate, socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Signaling.relay(room, from, target, :ice, %{candidate: candidate}) do
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
    with :ok <- check_ws_rate_limit(socket),
         :ok <- validate_signal_payload(sdp, socket) do
      room = socket.assigns.signaling_room
      from = socket.assigns.signaling_user_id

      case Signaling.broadcast(room, from, :offer, %{sdp: sdp, from_user_id: from}) do
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

      if Signaling.enabled?(room) do
        {:reply, {:ok, %{users: Signaling.peers(room)}}, socket}
      else
        Logger.warning("SignalingChannel: list_users failed room_not_found room=#{room}")
        {:stop, :normal, {:error, %{error: "room_not_found"}}, socket}
      end
    end
  end

  @impl true
  def handle_in(event, _payload, socket),
    do: ChannelEvents.unknown(event, socket, room: :signaling_room, user: :signaling_user_id)

  # ── Presence ─────────────────────────────────────────────────────────────

  # Presence diffs carry the cluster-wide view. Translated into this channel's
  # existing event names so the client protocol is unchanged.
  # Intercepted via `intercept ["presence_diff"]`
  @impl true
  def handle_out("presence_diff", payload, socket) do
    socket =
      socket
      |> announce_joins(payload.joins)
      |> schedule_leaves(payload.leaves)

    {:noreply, socket}
  end

  # Tracking happens after join so `Presence.track/3` sees a joined channel.
  # Subscribing to our own inbox is what makes relays work across nodes: the
  # sender broadcasts to `signaling:<room>:<user>` and whichever node holds
  # that socket delivers it.
  @impl true
  def handle_info(:after_signaling_join, socket) do
    %{signaling_room: room, signaling_user_id: user_id, signaling_role: role} = socket.assigns

    {:ok, _ref} =
      Presence.track(self(), Signaling.topic(room), user_id, %{
        role: role,
        joined_at: System.system_time(:second)
      })

    Phoenix.PubSub.subscribe(Gamend.PubSub, Signaling.inbox(room, user_id))

    # Seed the newcomer with everyone already here so it can start connecting.
    for {other_id, other_role} <- Signaling.peers(room), other_id != user_id do
      push_event(socket, "user_joined", %{user_id: other_id, role: other_role})
    end

    {:noreply, socket}
  end

  # A leave is only real if the peer is still gone once the grace has passed —
  # otherwise it was a reconnect, and tearing the WebRTC session down for a
  # two-second blip is exactly what `reconnect_timeout` exists to prevent.
  @impl true
  def handle_info({:confirm_leave, user_id}, socket) do
    room = socket.assigns.signaling_room
    socket = update_in(socket.assigns.pending_leaves, &Map.delete(&1, user_id))

    if is_nil(Signaling.peer_role(room, user_id)) do
      push_event(socket, "user_left", %{user_id: user_id})
    end

    {:noreply, socket}
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

      # Presence untracks on process exit, and peers debounce the leave for
      # `reconnect_timeout` before reporting it, so a reconnect is invisible.
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

  defp announce_joins(socket, joins) do
    me = socket.assigns.signaling_user_id

    Enum.reduce(joins, socket, fn {user_id, %{metas: metas}}, acc ->
      if user_id == me do
        acc
      else
        role = metas |> List.first() |> Map.get(:role, :user)
        {timer, pending} = Map.pop(acc.assigns.pending_leaves, user_id)

        # A join while a leave is pending is a reconnect, not a new peer.
        event = if timer, do: "user_rejoined", else: "user_joined"
        if timer, do: Process.cancel_timer(timer)

        push_event(acc, event, %{user_id: user_id, role: role})
        put_in(acc.assigns.pending_leaves, pending)
      end
    end)
  end

  defp schedule_leaves(socket, leaves) do
    me = socket.assigns.signaling_user_id
    grace = socket.assigns[:signaling_reconnect_timeout] || 0

    Enum.reduce(leaves, socket, fn {user_id, _}, acc ->
      if user_id == me do
        acc
      else
        timer = Process.send_after(self(), {:confirm_leave, user_id}, grace)
        put_in(acc.assigns.pending_leaves, Map.put(acc.assigns.pending_leaves, user_id, timer))
      end
    end)
  end

  defp reconnect_timeout(room) do
    case Signaling.config(room) do
      {:ok, %{reconnect_timeout: ms}} -> ms
      _ -> 0
    end
  end

  # ── WebSocket rate limiting ─────────────────────────────────────────────

  defp check_ws_rate_limit(socket) do
    if rate_setting(:enabled) do
      user_id = socket.assigns.current_scope.user_id
      limit = rate_setting(:signaling_ws_limit)
      window = rate_setting(:signaling_ws_window_ms)

      case GamendWeb.RateLimit.hit("signaling_ws:#{user_id}", window, limit) do
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
    if rate_setting(:enabled) do
      user_id = socket.assigns.current_scope.user_id
      limit = rate_setting(:signaling_ice_limit)
      window = rate_setting(:signaling_ice_window_ms)

      case GamendWeb.RateLimit.hit("signaling_ice:#{user_id}", window, limit) do
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

  # Unknown events are logged at debug with the name truncated, and the name is
  # never interpolated at warning level.
  #
  # Every other `handle_in/3` here rate-limits first; this catch-all did not,
  # and it put a client-chosen string into a warning line. A frame allows a
  # 128 KB event name, so one socket could drive unbounded warning-level volume
  # made of attacker-controlled text into the rotating log and the admin buffer.
  # Client-chosen, so never logged whole.

  # SDP and ICE candidates are relayed verbatim to other peers, so bound them
  # here rather than trusting whatever a frame can carry.
  #
  # These were passed through with no type or size check at all — they did not
  # even have to be strings, since any JSON term was forwarded — while the
  # socket allows a 128 KB frame. A real SDP offer is a few kilobytes and an ICE
  # candidate is a single line.
  @max_signal_bytes 16_384

  # Returns `:ok`, or a complete channel reply — the `with`s above have no
  # `else`, so a non-`:ok` value is returned to Phoenix as-is, the same way
  # `check_ws_rate_limit/1` signals a rejection.
  defp validate_signal_payload(value, socket) when is_binary(value) do
    if byte_size(value) <= @max_signal_bytes,
      do: :ok,
      else: {:reply, {:error, %{error: "payload_too_large"}}, socket}
  end

  defp validate_signal_payload(_value, socket),
    do: {:reply, {:error, %{error: "invalid_payload"}}, socket}

  defp rate_setting(key), do: Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, key)
end
