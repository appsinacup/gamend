defmodule GamendWeb.GroupsChannel do
  @moduledoc """
  Channel for broadcasting global group list events.

  Topic: "groups"

  Clients may join this topic to receive real-time notifications when groups
  are created, updated, or deleted. Hidden groups are excluded from broadcasts.

  ## Events pushed to clients

  - `"group_created"` - A new group was created. Payload: group object
  - `"group_updated"` - A group was updated. Payload: group object
  - `"group_deleted"` - A group was deleted. Payload: `%{id: integer}`
  """

  use Phoenix.Channel

  import GamendWeb.ChannelPush

  alias GamendWeb.ChannelEvents
  alias GamendWeb.ChannelUpdates
  alias GamendWeb.Plugs.FeatureGate
  alias GamendWeb.Serializers

  require Gamend.Groups.GroupType, as: GroupType
  require GamendWeb.ChannelError, as: ChannelError
  require GamendWeb.ChannelTopic, as: ChannelTopic
  require Gamend.Realtime.RealtimeEvent, as: RealtimeEvent

  # A banned account joins no channel but its own user channel.
  @impl true
  def join(topic, payload, socket) do
    with :ok <- GamendWeb.UserSocket.refuse_banned(socket),
         do: join_topic(topic, payload, socket)
  end

  defp join_topic(ChannelTopic.groups(), _payload, socket) do
    # Same flag as GET /api/v1/groups — the feed must not outlive the API.
    if FeatureGate.enabled?(:list_groups) do
      GamendWeb.ConnectionTracker.register(:groups_channel)
      {:ok, socket}
    else
      {:error, %{reason: ChannelError.listing_disabled()}}
    end
  end

  @impl true
  # Answer and stay up — see LobbyChannel: stopping the channel over one
  # unrecognised event took every broadcast it carried with it, and a client
  # cannot tell a dead channel from a quiet one.
  def handle_in(event, _payload, socket), do: ChannelEvents.unknown(event, socket)

  @impl true
  def handle_info({:group_created, group}, socket) do
    # Don't broadcast hidden groups to the public list channel
    if group.type != GroupType.hidden() do
      payload = Serializers.serialize_group(group)
      push_event(socket, RealtimeEvent.group_created(), payload)

      {:noreply,
       ChannelUpdates.remember(socket, RealtimeEvent.group_updated(), payload.id, payload)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:group_updated, group}, socket) do
    if group.type != GroupType.hidden() do
      payload = Serializers.serialize_group(group)
      {:noreply, ChannelUpdates.push(socket, RealtimeEvent.group_updated(), payload.id, payload)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:group_deleted, group_id}, socket) do
    push_event(socket, RealtimeEvent.group_deleted(), %{id: group_id})
    {:noreply, ChannelUpdates.forget(socket, RealtimeEvent.group_updated(), group_id)}
  end

  @impl true
  def handle_info(msg, socket), do: {:noreply, ChannelEvents.other_info(msg, socket)}
end
