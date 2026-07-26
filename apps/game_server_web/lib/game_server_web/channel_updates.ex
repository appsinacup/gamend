defmodule GameServerWeb.ChannelUpdates do
  @moduledoc """
  Outbound state-update pushes for channels: drop no-op updates, and optionally
  coalesce bursts into one message.

  State events re-send the current state of an object the subscriber already
  has, so two things are worth doing before pushing:

    * **Deduplicate.** If nothing changed since the last push on this
      connection, send nothing at all.
    * **Debounce.** When `REALTIME_DEBOUNCE_MS` is set, hold updates for that
      long and push only the latest state per object when the timer fires. A
      burst of ten writes to one lobby becomes one message.

  Debouncing is off by default (`0`), which pushes immediately and only
  deduplicates.

  Coalescing beats shrinking here: each WebSocket message costs roughly 76
  bytes of framing, TLS, TCP and IP headers before any payload, and the server
  runs with `TCP_NODELAY`, so every message is its own packet. Removing a
  message saves more than compressing one ever can.

  ## Usage

      def handle_info({:lobby_updated, lobby}, socket) do
        payload = Serializers.serialize_lobby(lobby)
        {:noreply, ChannelUpdates.push(socket, "lobby_updated", payload.id, payload)}
      end

      # required once per channel that pushes updates
      def handle_info({:channel_updates_flush, _}, socket),
        do: {:noreply, ChannelUpdates.flush(socket)}

  `key` scopes the dedupe/coalesce slot within the channel. Channels that track
  one object can pass any constant; channels that multiplex (`lobbies`,
  `groups`, member lists) must pass the object id.
  """

  import Phoenix.Socket, only: [assign: 3]

  alias GameServerWeb.ChannelPush

  @flush_message :channel_updates_flush

  @doc "Milliseconds to hold updates before pushing. 0 disables debouncing."
  @spec debounce_ms() :: non_neg_integer()
  def debounce_ms do
    GameServer.Settings.get(GameServerWeb.Realtime, :debounce_ms)
  end

  @doc """
  Pushes `payload` for `event`/`key`, unless it is identical to the last one
  pushed on this socket. Returns the updated socket.

  `wrap` builds the message body from the payload, for events that nest it
  (`friend_updated` sends `%{friends: %{id => payload}}`). Deduplication always
  compares the unwrapped payload.
  """
  @spec push(Phoenix.Socket.t(), String.t(), term(), map(), (map() -> map())) ::
          Phoenix.Socket.t()
  def push(socket, event, key, payload, wrap \\ & &1) do
    slot = {event, key}

    if unchanged?(socket, slot, payload) do
      socket
    else
      case debounce_ms() do
        ms when ms > 0 -> enqueue(socket, slot, {payload, wrap}, ms)
        _ -> push_now(socket, slot, {payload, wrap})
      end
    end
  end

  @doc "The last payload pushed for `event`/`key`, or nil."
  @spec last(Phoenix.Socket.t(), String.t(), term()) :: map() | nil
  def last(socket, event, key) do
    Map.get(socket.assigns, :cu_last, %{})[{event, key}]
  end

  @doc """
  Pushes every pending update. Call from the channel's handler for
  `#{inspect(@flush_message)}` messages.
  """
  @spec flush(Phoenix.Socket.t()) :: Phoenix.Socket.t()
  def flush(socket) do
    pending = Map.get(socket.assigns, :cu_pending, %{})

    socket
    |> assign(:cu_pending, %{})
    |> assign(:cu_timer, nil)
    |> then(fn socket ->
      # Sorted so a flush carrying several objects is deterministic.
      pending
      |> Enum.sort_by(fn {{event, key}, _entry} -> {event, inspect(key)} end)
      |> Enum.reduce(socket, fn {slot, entry}, acc -> push_now(acc, slot, entry) end)
    end)
  end

  @doc """
  Forgets everything remembered for `event`/`key`, so the next push is treated
  as the first one. Use when the object is deleted or the client leaves it.
  """
  @spec forget(Phoenix.Socket.t(), String.t(), term()) :: Phoenix.Socket.t()
  def forget(socket, event, key) do
    slot = {event, key}

    socket
    |> assign(:cu_last, Map.delete(Map.get(socket.assigns, :cu_last, %{}), slot))
    |> assign(:cu_pending, Map.delete(Map.get(socket.assigns, :cu_pending, %{}), slot))
  end

  @doc """
  Records `payload` as already delivered without pushing it, so a later
  identical update is suppressed. Use when the payload went out under a
  different event name (a create that doubles as the first update).
  """
  @spec remember(Phoenix.Socket.t(), String.t(), term(), map()) :: Phoenix.Socket.t()
  def remember(socket, event, key, payload) do
    last = Map.get(socket.assigns, :cu_last, %{})
    assign(socket, :cu_last, Map.put(last, {event, key}, payload))
  end

  @doc false
  def flush_message, do: @flush_message

  # ── internals ─────────────────────────────────────────────────────────────

  defp unchanged?(socket, slot, payload) do
    # Compare against the pending value when one is queued: that is what the
    # subscriber will receive next.
    pending = Map.get(socket.assigns, :cu_pending, %{})

    case Map.fetch(pending, slot) do
      {:ok, {queued, _wrap}} -> queued === payload
      :error -> Map.get(socket.assigns, :cu_last, %{})[slot] === payload
    end
  end

  defp push_now(socket, {event, _key} = slot, {payload, wrap}) do
    # Format-aware: protobuf sockets get a binary frame, everyone else JSON.
    ChannelPush.push_event(socket, event, wrap.(payload))

    last = Map.get(socket.assigns, :cu_last, %{})
    assign(socket, :cu_last, Map.put(last, slot, payload))
  end

  defp enqueue(socket, slot, entry, ms) do
    pending = Map.get(socket.assigns, :cu_pending, %{})

    socket
    |> assign(:cu_pending, Map.put(pending, slot, entry))
    |> ensure_timer(ms)
  end

  # One timer per channel, not per object: a flush drains everything pending,
  # so a busy channel still sends at most one message per window per object.
  defp ensure_timer(socket, ms) do
    case Map.get(socket.assigns, :cu_timer) do
      nil ->
        ref = Process.send_after(self(), {@flush_message, :all}, ms)
        assign(socket, :cu_timer, ref)

      _ref ->
        socket
    end
  end
end
