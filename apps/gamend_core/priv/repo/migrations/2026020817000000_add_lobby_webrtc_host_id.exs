defmodule Gamend.Repo.Migrations.AddLobbyWebrtcHostId do
  use Ecto.Migration

  @doc """
  Adds `webrtc_host_id` as an independent UUIDv7 identity for the WebRTC star
  host. It is intentionally not a foreign key to `users`, so it can also
  represent dedicated server processes, bots, or other non-user entities.
  """
  def change do
    alter table(:lobbies) do
      add :webrtc_host_id, :binary_id
    end
  end
end
