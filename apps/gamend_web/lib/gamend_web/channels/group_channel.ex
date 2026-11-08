defmodule GamendWeb.GroupChannel do
  @moduledoc """
  Channel for per-group realtime events.

  Topic: "group:<group_id>"

  Only users who are members of the group may join this channel.

  ## Events pushed to clients

  - `"member_joined"` - A user joined the group. Payload: `%{group_id, user_id}`
  - `"member_left"` - A user left the group. Payload: `%{group_id, user_id}`
  - `"member_kicked"` - A user was kicked. Payload: `%{group_id, user_id}`
  - `"member_promoted"` - A user was promoted to admin. Payload: `%{group_id, user_id}`
  - `"member_demoted"` - A user was demoted to member. Payload: `%{group_id, user_id}`
  - `"updated"` - Group settings were updated. Payload: group object
  - `"join_request_approved"` - A join request was approved. Payload: `%{group_id, user_id}`
  - `"join_request_rejected"` - A join request was rejected. Payload: `%{group_id, user_id}`
  - `"chat_message_created"` - A new chat message. Payload: chat message object
  - `"chat_message_updated"` - A chat message was updated. Payload: chat message object
  - `"chat_message_deleted"` - A chat message was deleted. Payload: `%{id: integer}`
  - `"member_updated"` - A group member was updated. Payload: user brief object
  - `"member_online"` - A group member came online. Payload: `%{user_id, is_online: true}`
  - `"member_offline"` - A group member went offline. Payload: `%{user_id, is_online: false}`
  """

  use Phoenix.Channel

  import GamendWeb.ChannelPush

  alias Gamend.Accounts.Scope
  alias Gamend.Chat
  alias Gamend.Groups
  alias GamendWeb.ChannelEvents
  alias GamendWeb.ChannelUpdates
  alias GamendWeb.Serializers

  require Gamend.RealtimeEvent, as: RealtimeEvent

  # A banned account joins no channel but its own user channel.
  @impl true
  def join(topic, payload, socket) do
    with :ok <- GamendWeb.UserSocket.refuse_banned(socket),
         do: join_topic(topic, payload, socket)
  end

  defp join_topic("group:" <> group_id_str, _payload, socket) do
    current_scope = Map.get(socket.assigns, :current_scope)

    # The group is read after the membership check: deleted in between, the
    # join is refused like any other, where a `get_group!` crashed it.
    with {:ok, group_id} <- Ecto.UUID.cast(group_id_str),
         %Scope{user_id: user_id} <- current_scope,
         true <- Groups.member?(group_id, user_id),
         %Groups.Group{} = group <- Groups.get_group(group_id) do
      Chat.subscribe_group_chat(group_id)

      GamendWeb.ConnectionTracker.register(:group_channel, %{
        group_id: group_id,
        user_id: user_id
      })

      send(self(), {:after_join, group})

      {:ok, assign(socket, :group_id, group_id)}
    else
      _ ->
        {:error, %{reason: "not_a_member_or_invalid"}}
    end
  end

  @impl true
  # Answer and stay up — see LobbyChannel: stopping the channel over one
  # unrecognised event took every broadcast it carried with it, and a client
  # cannot tell a dead channel from a quiet one.
  def handle_in(event, _payload, socket),
    do: ChannelEvents.unknown(event, socket, group: :group_id)

  # ── PubSub → WebSocket ────────────────────────────────────────────────────

  @impl true
  def handle_info({:after_join, group}, socket) do
    payload = Serializers.serialize_group(group)
    push_event(socket, RealtimeEvent.updated(), payload)
    {:noreply, ChannelUpdates.remember(socket, RealtimeEvent.updated(), :group, payload)}
  end

  @impl true
  def handle_info({:group_updated, group}, socket) do
    payload = Serializers.serialize_group(group)
    {:noreply, ChannelUpdates.push(socket, RealtimeEvent.updated(), :group, payload)}
  end

  @impl true
  def handle_info({:member_joined, group_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_joined(), %{
      group_id: group_id,
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:member_left, group_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_left(), %{
      group_id: group_id,
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    stop_if_own_departure(socket, user_id)
  end

  @impl true
  def handle_info({:member_kicked, group_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_kicked(), %{
      group_id: group_id,
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    stop_if_own_departure(socket, user_id)
  end

  @impl true
  def handle_info({:member_promoted, group_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_promoted(), %{
      group_id: group_id,
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:member_demoted, group_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_demoted(), %{
      group_id: group_id,
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:join_request_approved, group_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.join_request_approved(), %{
      group_id: group_id,
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:join_request_rejected, group_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.join_request_rejected(), %{
      group_id: group_id,
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_message_created, message}, socket) do
    push_event(
      socket,
      RealtimeEvent.chat_message_created(),
      Serializers.serialize_chat_message(message)
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_message_updated, message}, socket) do
    push_event(
      socket,
      RealtimeEvent.chat_message_updated(),
      Serializers.serialize_chat_message(message)
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_message_deleted, message}, socket) do
    push_event(socket, RealtimeEvent.chat_message_deleted(), %{id: message.id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:member_updated, user_id}, socket),
    do:
      {:noreply,
       ChannelEvents.push_member_updated(socket, user_id, RealtimeEvent.member_updated())}

  @impl true
  def handle_info({:member_online, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_online(), %{user_id: user_id, is_online: true})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:member_offline, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_offline(), %{user_id: user_id, is_online: false})
    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket), do: {:noreply, ChannelEvents.other_info(msg, socket)}

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns do
      %{group_id: group_id} when is_binary(group_id) ->
        Chat.unsubscribe_group_chat(group_id)
        :ok

      _ ->
        :ok
    end
  end

  # Joining requires membership, so losing it has to end the channel — otherwise
  # a kicked member keeps receiving this group's state and chat indefinitely,
  # including for a hidden group they can no longer see or rejoin. The event is
  # pushed first so the client knows why the channel closed.
  defp stop_if_own_departure(socket, user_id) do
    if user_id == socket.assigns.current_scope.user_id do
      {:stop, :normal, socket}
    else
      {:noreply, socket}
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
end
