defmodule GameServer.Signaling do
  @moduledoc """
  Public API for the WebRTC signaling broker.

  This module is exposed to plugins through the SDK. All operations are
  forwarded to the internal GameServerWeb.SignalingBroker process.
  """

  alias GameServerWeb.SignalingBroker

  def create_room(room_id, topology, opts \\ []) do
    SignalingBroker.create_room(room_id, topology, opts)
  end

  def close_room(room_id) do
    SignalingBroker.close_room(room_id)
  end

  def exists_room?(room_id) do
    SignalingBroker.exists_room?(room_id)
  end

  def allow_user(room_id, user_id, role \\ :user) do
    SignalingBroker.allow_user(room_id, user_id, role)
  end

  def disallow_user(room_id, user_id) do
    SignalingBroker.disallow_user(room_id, user_id)
  end

  def list_users(room_id) do
    SignalingBroker.list_users(room_id)
  end

  def get_room(room_id) do
    SignalingBroker.get_room(room_id)
  end

  def update_room_host(room_id, new_host_user_id) do
    SignalingBroker.update_room_host(room_id, new_host_user_id)
  end
end
