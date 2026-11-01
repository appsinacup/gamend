defmodule Gamend.Repo.Migrations.CreateMatchmakingTickets do
  use Ecto.Migration

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
