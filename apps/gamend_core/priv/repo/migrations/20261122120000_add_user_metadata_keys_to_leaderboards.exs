defmodule Gamend.Repo.Migrations.AddUserMetadataKeysToLeaderboards do
  @moduledoc """
  `leaderboards.user_metadata_keys`: the paths into each player's
  `users.metadata` the board's rows carry (`player.pass_level`), read when
  the row is. Empty, the default, sends none. A JSON array on SQLite, a
  `text[]` on Postgres.
  """

  use Ecto.Migration

  def change do
    alter table(:leaderboards) do
      add :user_metadata_keys, {:array, :string}, null: false, default: []
    end
  end
end
