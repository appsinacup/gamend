defmodule GameServer.Signaling do
  @moduledoc """
  Public API for the WebRTC signaling server.

  This module is exposed to plugins through the SDK. All operations are
  forwarded to the internal GameServerWeb.SignalingServer process.
  """

  alias GameServerWeb.SignalingServer

  def create_room(room_id, topology, opts \\ []) do
    SignalingServer.create_room(room_id, topology, opts)
  end

  def close_room(room_id) do
    SignalingServer.close_room(room_id)
  end

  def exists_room?(room_id) do
    SignalingServer.exists_room?(room_id)
  end

  def allow_user(room_id, user_id, role \\ :user) do
    SignalingServer.allow_user(room_id, user_id, role)
  end

  def disallow_user(room_id, user_id) do
    SignalingServer.disallow_user(room_id, user_id)
  end

  def list_users(room_id) do
    SignalingServer.list_users(room_id)
  end

  def get_room(room_id) do
    SignalingServer.get_room(room_id)
  end

  def update_room_host(room_id, new_host_user_id) do
    SignalingServer.update_room_host(room_id, new_host_user_id)
  end
end
