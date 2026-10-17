defmodule Gamend.Repo.Migrations.CreateAnalyticsEvents do
  use Ecto.Migration

  # One row per thing a player did that a question might be asked about
  # later: a round started, a test finished, a page viewed. The daily
  # counters beside it (`analytics_daily_counts`) answer "how many"; this
  # table answers everything they cannot — how many DISTINCT people, in what
  # order, with which other things — because it keeps who and when.
  #
  # `dims` is the event's own fields (language, game, score…) as a map, so a
  # new field is a new key, never a migration. `user_id` is nulled, not
  # cascaded, when the account goes: the round still happened and the day's
  # counts must not shrink retroactively, while nothing is left that names
  # a person. Pruned by `Gamend.Retention` (`analytics_events_days`).
  def change do
    create table(:analytics_events) do
      add :name, :string, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :dims, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Grafana and the admin page read a window of days, usually by name.
    create index(:analytics_events, [:inserted_at])
    create index(:analytics_events, [:name, :inserted_at])
    # The nilify on account deletion, and "what did this person do".
    create index(:analytics_events, [:user_id])
  end
end
