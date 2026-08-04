defmodule Gamend.Repo.Migrations.AddLobbyWebrtcHostId do
  use Ecto.Migration

  @doc """
  Adds `webrtc_host_id` so the WebRTC signaling host can be set independently
  from the lobby host. If `null`, Signaling falls back to `lobby.host_id`.
  """
  def change do
    alter table(:lobbies) do
      add :webrtc_host_id, references(:users, on_delete: :nilify_all)
    end
  end
end
