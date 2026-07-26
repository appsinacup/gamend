defmodule GameServer.Repo.Migrations.AddNotificationIconUrl do
  use Ecto.Migration

  # Brings notifications level with groups, tournaments, leaderboards and
  # quests. Nullable: the UI falls back to the typed default icon
  # (GameServerWeb.Icons), so no backfill is needed.
  def change do
    alter table(:notifications) do
      add :icon_url, :string
    end
  end
end
