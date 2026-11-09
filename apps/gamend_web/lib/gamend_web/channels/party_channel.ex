defmodule GamendWeb.PartyChannel do
  @moduledoc """
  Channel for party realtime events.

  Topic: "party:<party_id>"

  Only users who are members of the party may join this channel.
  Membership is determined by the user's `party_id` field.

  ## Events pushed to clients

  - `"member_joined"` - A user joined the party. Payload: `%{user_id: integer}`
  - `"member_left"` - A user left or was kicked from the party. Payload: `%{user_id: integer}`
  - `"member_online"` - A party member came online. Payload: user brief object
  - `"member_offline"` - A party member went offline. Payload: user brief object
  - `"member_updated"` - A party member was updated. Payload: user brief object
  - `"updated"` - The party settings were updated. Payload: party object
  - `"disbanded"` - The party was disbanded. Payload: `%{party_id: integer}`
  - `"ready_check_started"` / `"ready_check_updated"` / `"ready_check_passed"`
    / `"ready_check_failed"` - The party's ready board changed. Payload: ready
    check object (see `GamendWeb.Serializers.serialize_ready_check/2`)
  - `"chat_message_created"` - A new chat message. Payload: chat message object
  - `"chat_message_updated"` - A chat message was updated. Payload: chat message object
  - `"chat_message_deleted"` - A chat message was deleted. Payload: `%{id: integer}`
  """

  use Phoenix.Channel

  import GamendWeb.ChannelPush
  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Chat
  alias Gamend.Parties
  alias GamendWeb.ChannelEvents
  alias GamendWeb.ChannelUpdates
  alias GamendWeb.Serializers

  require GamendWeb.ChannelError, as: ChannelError
  require Gamend.Realtime.RealtimeEvent, as: RealtimeEvent

  # A banned account joins no channel but its own user channel.
  @impl true
  def join(topic, payload, socket) do
    with :ok <- GamendWeb.UserSocket.refuse_banned(socket),
         do: join_topic(topic, payload, socket)
  end

  defp join_topic("party:" <> party_id_str, _payload, socket) do
    current_scope = Map.get(socket.assigns, :current_scope)

    with {:ok, party_id} <- Ecto.UUID.cast(party_id_str),
         %Scope{user_id: user_id} <- current_scope do
      case Accounts.get_user(user_id) do
        %User{party_id: ^party_id} ->
          Chat.subscribe_party_chat(party_id)

          GamendWeb.ConnectionTracker.register(:party_channel, %{
            party_id: party_id,
            user_id: user_id
          })

          party = Parties.get_party(party_id)
          send(self(), {:after_join, party})
          {:ok, socket |> assign(:party_id, party_id)}

        _ ->
          Logger.info(
            "PartyChannel: user #{user_id} attempted to join party #{party_id} but is not a member"
          )

          {:error, %{reason: "not_a_member"}}
      end
    else
      _ ->
        {:error, %{reason: ChannelError.invalid_topic_or_unauthenticated()}}
    end
  end

  @impl true
  # Answer and stay up — see LobbyChannel: stopping the channel over one
  # unrecognised event took every broadcast it carried with it, and a client
  # cannot tell a dead channel from a quiet one.
  def handle_in(event, _payload, socket),
    do: ChannelEvents.unknown(event, socket, party: :party_id)

  # Handle PubSub messages and forward them to WebSocket clients

  @impl true
  def handle_info({:party_member_joined, _party_id, user_id}, socket) do
    user = Accounts.get_user(user_id)

    payload =
      if user do
        User.serialize_brief(user) |> Map.put(:user_id, user_id)
      else
        %{user_id: user_id, display_name: ""}
      end

    push_event(socket, RealtimeEvent.member_joined(), payload)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:party_member_left, _party_id, user_id}, socket) do
    push_event(socket, RealtimeEvent.member_left(), %{
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    # Joining pins `party_id` against a freshly-read user, so a member who has
    # left (or been kicked) must not keep the channel and its chat.
    if user_id == socket.assigns.current_scope.user_id do
      {:stop, :normal, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:party_updated, %Gamend.Parties.Party{} = party}, socket) do
    payload = Serializers.serialize_party(party)
    {:noreply, ChannelUpdates.push(socket, RealtimeEvent.updated(), :party, payload)}
  end

  @impl true
  def handle_info({:party_updated, party_id}, socket) when is_binary(party_id) do
    case Parties.get_party(party_id) do
      nil ->
        {:noreply, socket}

      party ->
        payload = Serializers.serialize_party(party)
        {:noreply, ChannelUpdates.push(socket, RealtimeEvent.updated(), :party, payload)}
    end
  end

  @impl true
  def handle_info({:party_disbanded, party_id}, socket) do
    push_event(socket, RealtimeEvent.disbanded(), %{party_id: party_id})
    {:noreply, socket}
  end

  # Same shape as the lobby channel: a burst of members readying at once
  # coalesces into one frame; a resolution is never held in the debounce timer.
  @impl true
  def handle_info(
        {:ready_check_event, RealtimeEvent.ready_check_updated() = event, check},
        socket
      ) do
    payload = serialize_ready_check(check, socket)
    {:noreply, ChannelUpdates.push(socket, event, check.id, payload)}
  end

  @impl true
  def handle_info({:ready_check_event, event, check}, socket) do
    push_event(socket, event, serialize_ready_check(check, socket))
    {:noreply, socket}
  end

  # Chat messages forwarded from PubSub

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
  def handle_info({event, user_id}, socket) when event in [:member_online, :member_offline] do
    wire =
      if event == :member_online,
        do: RealtimeEvent.member_online(),
        else: RealtimeEvent.member_offline()

    {:noreply, ChannelEvents.push_presence(socket, event, user_id, wire)}
  end

  @impl true
  def handle_info({:member_updated, user_id}, socket),
    do:
      {:noreply,
       ChannelEvents.push_member_updated(socket, user_id, RealtimeEvent.member_updated())}

  @impl true
  def handle_info({:after_join, nil}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:after_join, party}, socket) do
    payload = Serializers.serialize_party(party)
    push_event(socket, RealtimeEvent.updated(), payload)
    {:noreply, ChannelUpdates.remember(socket, RealtimeEvent.updated(), :party, payload)}
  end

  @impl true
  def handle_info(msg, socket), do: {:noreply, ChannelEvents.other_info(msg, socket)}

  defp serialize_ready_check(check, socket) do
    viewer_id = get_in(socket.assigns, [:current_scope, Access.key(:user_id)])
    Serializers.serialize_ready_check(check, viewer_id: viewer_id)
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns do
      %{party_id: party_id} when is_binary(party_id) ->
        _ = Chat.unsubscribe_party_chat(party_id)
        :ok

      _ ->
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
end
