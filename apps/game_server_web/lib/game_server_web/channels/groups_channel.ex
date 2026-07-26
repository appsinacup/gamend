defmodule GameServerWeb.GroupsChannel do
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

  import GameServerWeb.ChannelPush

  alias GameServer.Groups
  alias GameServerWeb.ChannelUpdates
  alias GameServerWeb.Plugs.FeatureGate
  alias GameServerWeb.Serializers

  @impl true
  def join("groups", _payload, socket) do
    # Same flag as GET /api/v1/groups — the feed must not outlive the API.
    if FeatureGate.enabled?(:list_groups) do
      GameServerWeb.ConnectionTracker.register(:groups_channel)
      Groups.subscribe_groups()
      {:ok, socket}
    else
      {:error, %{reason: "listing_disabled"}}
    end
  end

  @impl true
  def handle_in(_event, _payload, socket),
    do: {:stop, :normal, {:error, %{error: "unknown_event"}}, socket}

  @impl true
  def handle_info({:group_created, group}, socket) do
    # Don't broadcast hidden groups to the public list channel
    if group.type != "hidden" do
      payload = Serializers.serialize_group(group)
      push_event(socket, "group_created", payload)
      {:noreply, ChannelUpdates.remember(socket, "group_updated", payload.id, payload)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:group_updated, group}, socket) do
    if group.type != "hidden" do
      payload = Serializers.serialize_group(group)
      {:noreply, ChannelUpdates.push(socket, "group_updated", payload.id, payload)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:group_deleted, group_id}, socket) do
    push_event(socket, "group_deleted", %{id: group_id})
    {:noreply, ChannelUpdates.forget(socket, "group_updated", group_id)}
  end

  @impl true
  def handle_info({:channel_updates_flush, _}, socket),
    do: {:noreply, ChannelUpdates.flush(socket)}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}
end
