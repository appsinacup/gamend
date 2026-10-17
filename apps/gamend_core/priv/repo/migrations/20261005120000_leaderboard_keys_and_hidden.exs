defmodule Gamend.Repo.Migrations.LeaderboardKeysAndHidden do
  @moduledoc """
  Two things a host needs to keep many scores on one board without making a
  board for each:

    * `leaderboard_records.key` — a record is unique per user (or label) AND
      key, and every ranking is within one key. A board with keys holds one
      best per player per key (a word game's settings, say), each ranked on
      its own; the metadata says what the key means so a reader can also
      merge keys (`Leaderboards.list_records/2`, `key: :all`). Every existing
      record gets `""`, which is how every board ranked until now.
    * `leaderboards.hidden` — a real board, ranked and readable by id or slug,
      that is left out of every public listing (the leaderboards page, the
      API index) because the host shows it on its own pages.
  """
  use Ecto.Migration

  def change do
    alter table(:leaderboards) do
      add :hidden, :boolean, null: false, default: false
    end

    alter table(:leaderboard_records) do
      add :key, :string, null: false, default: ""
    end

    drop unique_index(:leaderboard_records, [:leaderboard_id, :user_id])

    drop unique_index(:leaderboard_records, [:leaderboard_id, :label],
           name: :leaderboard_records_leaderboard_id_label_index
         )

    create unique_index(:leaderboard_records, [:leaderboard_id, :user_id, :key])
    create unique_index(:leaderboard_records, [:leaderboard_id, :label, :key])

    # The rank index, now within a key: every ranking query filters on it.
    drop index(:leaderboard_records, [:leaderboard_id, :score, :inserted_at],
           name: :leaderboard_records_rank_index
         )

    create index(:leaderboard_records, [:leaderboard_id, :key, :score, :inserted_at],
             name: :leaderboard_records_rank_index
           )
  end
end
