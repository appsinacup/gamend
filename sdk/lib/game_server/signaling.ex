defmodule GameServer.Signaling do
  @moduledoc "SDK stub for GameServer.Signaling."

  def create_room(_room_id, _topology, _opts \\ []), do: :ok
  def close_room(_room_id), do: :ok
  def room_exists?(_room_id), do: false
  def allow_user(_room_id, _user_id, _role \\ :peer), do: :ok
  def disallow_user(_room_id, _user_id), do: :ok
  def list_peers(_room_id), do: %{}
  def get_room(_room_id), do: {:error, :room_not_found}
  def update_room_host(_room_id, _new_host_user_id), do: :ok
end
