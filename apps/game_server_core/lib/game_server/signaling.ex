defmodule GameServer.Signaling do
  @moduledoc """
  Public API for the WebRTC signaling server.

  This module delegates to `GameServer.Signaling.Server`, which is the
  GenServer that actually manages rooms and relays messages.
  """

  alias GameServer.Signaling.Server

  def create_room(room_id, topology, opts \\ []) when topology in [:mesh, :star] do
    Server.create_room(room_id, topology, opts)
  end

  def close_room(room_id) do
    Server.close_room(room_id)
  end

  def exists_room?(room_id) do
    Server.exists_room?(room_id)
  end

  def join_room(room_id, user_id, pid, metadata \\ %{})
      when is_binary(room_id) and is_binary(user_id) and is_pid(pid) do
    Server.join_room(room_id, user_id, pid, metadata)
  end

  def leave_room(room_id, user_id) when is_binary(room_id) and is_binary(user_id) do
    Server.leave_room(room_id, user_id)
  end

  def allow_user(room_id, user_id, role \\ :user) do
    Server.allow_user(room_id, user_id, role)
  end

  def disallow_user(room_id, user_id) do
    Server.disallow_user(room_id, user_id)
  end

  def relay_message(room_id, from_user_id, to_user_id, type, payload) do
    Server.relay_message(room_id, from_user_id, to_user_id, type, payload)
  end

  def broadcast_message(room_id, from_user_id, type, payload) do
    Server.broadcast_message(room_id, from_user_id, type, payload)
  end

  def list_users(room_id) do
    Server.list_users(room_id)
  end

  def room_host?(room_id, user_id) do
    Server.room_host?(room_id, user_id)
  end

  def get_room(room_id) do
    Server.get_room(room_id)
  end

  def update_room_host(room_id, new_host_user_id) do
    Server.update_room_host(room_id, new_host_user_id)
  end
end
