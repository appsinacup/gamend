defmodule Gamend.Repo.Migrations.CreateMatchmakingTickets do
  use Ecto.Migration

  # Drift, accepted (2026-11-13): until 48ba1dbe5 (2026-11-01) this declared
  # its own `:binary_id` key, which SQLite leaves nullable (only an INTEGER
  # PRIMARY KEY is NOT NULL there); since, the table takes the repo's
  # `migration_primary_key` (`null: false`). SQLite databases created before
  # keep a nullable `id`. Every insert gives one, and SQLite cannot alter a
  # column in place, so they are left. Postgres makes a primary key NOT NULL
  # either way.
  def change do
    create table(:matchmaking_tickets) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :match_params, :map, null: false, default: "{}"
      add :min_players, :integer, null: false
      add :max_players, :integer, null: false
      add :timeout_ms, :integer, null: false
      add :queued_at, :utc_datetime_usec, null: false
      add :matched_at, :utc_datetime_usec
      add :match_id, references(:lobbies, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:matchmaking_tickets, [:status, :queued_at])
    create index(:matchmaking_tickets, [:user_id, :status])
  end
end
