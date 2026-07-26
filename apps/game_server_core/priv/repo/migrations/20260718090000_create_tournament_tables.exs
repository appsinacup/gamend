defmodule GameServer.Repo.Migrations.CreateTournamentTables do
  use Ecto.Migration

  def change do
    create table(:tournaments) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :description, :string, default: "", null: false
      add :state, :string, default: "scheduled", null: false
      add :registration_opens_at, :utc_datetime
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :recur, :string
      add :max_entries, :integer
      add :team_size, :integer, default: 1, null: false
      add :bracket_size, :integer, default: 8, null: false
      add :round_window_sec, :integer, null: false
      add :deadline_policy, :string, default: "forfeit_both", null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tournaments, [:slug])
    create index(:tournaments, [:state])

    create table(:tournament_entries) do
      add :tournament_id, references(:tournaments, on_delete: :delete_all), null: false
      add :leader_id, references(:users, on_delete: :delete_all), null: false
      add :seed, :integer
      add :bracket_index, :integer
      add :wins, :integer, default: 0, null: false
      add :state, :string, default: "registered", null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tournament_entries, [:tournament_id, :leader_id])
    create index(:tournament_entries, [:leader_id])
    create index(:tournament_entries, [:state])

    create table(:tournament_brackets) do
      add :tournament_id, references(:tournaments, on_delete: :delete_all), null: false
      add :index, :integer, null: false
      add :size, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:tournament_brackets, [:tournament_id, :index])

    create table(:tournament_matches) do
      add :tournament_id, references(:tournaments, on_delete: :delete_all), null: false
      add :bracket_index, :integer, null: false
      add :round, :integer, null: false
      add :slot, :integer, null: false
      add :a_entry_id, references(:tournament_entries, on_delete: :nilify_all)
      add :b_entry_id, references(:tournament_entries, on_delete: :nilify_all)
      add :winner_entry_id, references(:tournament_entries, on_delete: :nilify_all)
      add :ready_at, :utc_datetime
      add :expired_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :deadline_at, :utc_datetime, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tournament_matches, [:tournament_id, :bracket_index, :round, :slot])
    create index(:tournament_matches, [:tournament_id])

    # Sweeps and dashboards only ever look at open matches.
    create index(:tournament_matches, [:deadline_at], where: "resolved_at IS NULL")
  end
end
