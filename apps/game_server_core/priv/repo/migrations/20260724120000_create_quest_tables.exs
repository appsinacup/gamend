defmodule GameServer.Repo.Migrations.CreateQuestTables do
  @moduledoc """
  Quests/progression engine tables, folding achievements in as permanent
  (`reset: "never"`) quests categorised `"achievement"`
  (see docs/specs/quests-progression.md):

  - `quests` — definitions (reset cycle, optional window, optional prerequisite).
  - `quest_progress` — per user per quest per reset period.
  - `inventory_ledger` — audit + idempotency for item grants, mirroring
    `ledger_entries`, so quest item rewards can be exactly-once.

  Achievement definitions/progress are copied over (same ids; an unlocked
  achievement becomes a claimed static-period progress row) and the old
  tables are dropped. The dead `achievements.points` column is not carried.
  """
  use Ecto.Migration

  def up do
    create table(:quests) do
      add :key, :string, null: false
      add :title, :string, null: false
      add :description, :string, default: ""
      add :icon_url, :string
      add :sort_order, :integer, default: 0
      add :hidden, :boolean, default: false
      # Orthogonal by design: `reset` is the only thing that drives period
      # bucketing; a time window is starts_at/ends_at and a chain is
      # prerequisite_quest_key, so any quest can be either or both.
      add :reset, :string, null: false, default: "never"
      add :reset_interval_days, :integer
      add :category, :string
      # A bare [] default is rejected by Postgres DDL; the quoted fragment
      # works on both adapters. An uncast embed inserts NULL, so keep both.
      add :objectives, :map, null: false, default: fragment("'[]'")
      add :rewards, :map, null: false, default: fragment("'[]'")
      add :auto_claim, :boolean, default: false, null: false
      add :prerequisite_quest_key, :string
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :active, :boolean, default: true, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quests, [:key])
    create index(:quests, [:category])
    create index(:quests, [:reset])
    create index(:quests, [:active], where: "active")

    create table(:quest_progress) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :quest_key,
          references(:quests, column: :key, type: :string, on_delete: :delete_all),
          null: false

      add :period_key, :string, null: false
      add :objective_progress, :map, default: %{}, null: false
      add :status, :string, null: false, default: "active"
      add :completed_at, :utc_datetime
      add :claimed_at, :utc_datetime
      add :rewards_granted_at, :utc_datetime
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quest_progress, [:user_id, :quest_key, :period_key])
    create index(:quest_progress, [:quest_key])
    # Claimable badge / listing.
    create index(:quest_progress, [:user_id], where: "status = 'completed'")
    # Admin dashboard "today" counters.
    create index(:quest_progress, [:completed_at])
    create index(:quest_progress, [:claimed_at])
    # Reward-recovery sweep: claimed but the post-commit grants never finished.
    create index(:quest_progress, [:claimed_at],
             name: :quest_progress_pending_rewards_index,
             where: "status = 'claimed' AND rewards_granted_at IS NULL"
           )

    create table(:inventory_ledger) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item, :string, null: false
      add :delta, :bigint, null: false
      add :quantity_after, :bigint, null: false
      add :reason, :string, null: false, default: "unspecified"
      add :idempotency_key, :string
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:inventory_ledger, [:user_id, :item])
    create index(:inventory_ledger, [:user_id, :inserted_at])

    create unique_index(:inventory_ledger, [:idempotency_key],
             where: "idempotency_key IS NOT NULL"
           )

    fold_achievements_in()

    drop table(:user_achievements)
    drop table(:achievements)
  end

  def down do
    create table(:achievements) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :description, :string, default: ""
      add :icon_url, :string
      add :points, :integer, default: 0
      add :sort_order, :integer, default: 0
      add :hidden, :boolean, default: false
      add :progress_target, :integer, default: 1
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:achievements, [:slug])

    create table(:user_achievements) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :achievement_id, references(:achievements, on_delete: :delete_all), null: false
      add :progress, :integer, default: 0
      add :unlocked_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_achievements, [:user_id, :achievement_id])
    create index(:user_achievements, [:user_id])
    create index(:user_achievements, [:achievement_id])

    unfold_achievements()

    drop table(:inventory_ledger)
    drop table(:quest_progress)
    drop table(:quests)
  end

  # Definitions keep their ids; each becomes a single-objective quest whose
  # event is the old slug, so increment_progress(user, slug, n) maps 1:1 to
  # report_event(user, slug, n). Unlocked progress lands terminal ("claimed",
  # rewards_granted_at set) so migrated rows never enter the claim/sweep paths.
  defp fold_achievements_in do
    if postgres?() do
      execute("""
      INSERT INTO quests (id, key, title, description, icon_url, sort_order, hidden, reset, category,
                          objectives, rewards, auto_claim, active, metadata, inserted_at, updated_at)
      SELECT id, slug, title, COALESCE(description, ''), icon_url, COALESCE(sort_order, 0),
             COALESCE(hidden, false), 'never', 'achievement',
             jsonb_build_array(jsonb_build_object('event', slug, 'target', COALESCE(progress_target, 1))),
             '[]'::jsonb, true, true, COALESCE(metadata, '{}'::jsonb), inserted_at, updated_at
      FROM achievements
      """)

      execute("""
      INSERT INTO quest_progress (id, user_id, quest_key, period_key, objective_progress, status,
                                  completed_at, claimed_at, rewards_granted_at, metadata,
                                  inserted_at, updated_at)
      SELECT ua.id, ua.user_id, a.slug, 'static',
             jsonb_build_object('0', COALESCE(ua.progress, 0)),
             CASE WHEN ua.unlocked_at IS NOT NULL THEN 'claimed' ELSE 'active' END,
             ua.unlocked_at, ua.unlocked_at, ua.unlocked_at, COALESCE(ua.metadata, '{}'::jsonb),
             ua.inserted_at, ua.updated_at
      FROM user_achievements ua JOIN achievements a ON a.id = ua.achievement_id
      """)
    else
      execute("""
      INSERT INTO quests (id, key, title, description, icon_url, sort_order, hidden, reset, category,
                          objectives, rewards, auto_claim, active, metadata, inserted_at, updated_at)
      SELECT id, slug, title, COALESCE(description, ''), icon_url, COALESCE(sort_order, 0),
             COALESCE(hidden, 0), 'never', 'achievement',
             json_array(json_object('event', slug, 'target', COALESCE(progress_target, 1))),
             '[]', 1, 1, COALESCE(metadata, '{}'), inserted_at, updated_at
      FROM achievements
      """)

      execute("""
      INSERT INTO quest_progress (id, user_id, quest_key, period_key, objective_progress, status,
                                  completed_at, claimed_at, rewards_granted_at, metadata,
                                  inserted_at, updated_at)
      SELECT ua.id, ua.user_id, a.slug, 'static',
             json_object('0', COALESCE(ua.progress, 0)),
             CASE WHEN ua.unlocked_at IS NOT NULL THEN 'claimed' ELSE 'active' END,
             ua.unlocked_at, ua.unlocked_at, ua.unlocked_at, COALESCE(ua.metadata, '{}'),
             ua.inserted_at, ua.updated_at
      FROM user_achievements ua JOIN achievements a ON a.id = ua.achievement_id
      """)
    end
  end

  defp unfold_achievements do
    if postgres?() do
      execute("""
      INSERT INTO achievements (id, slug, title, description, icon_url, points, sort_order,
                                hidden, progress_target, metadata, inserted_at, updated_at)
      SELECT id, key, title, description, icon_url, 0, sort_order, hidden,
             COALESCE((objectives->0->>'target')::int, 1), metadata, inserted_at, updated_at
      FROM quests WHERE category = 'achievement'
      """)

      execute("""
      INSERT INTO user_achievements (id, user_id, achievement_id, progress, unlocked_at,
                                     metadata, inserted_at, updated_at)
      SELECT qp.id, qp.user_id, q.id, COALESCE((qp.objective_progress->>'0')::int, 0),
             qp.completed_at, qp.metadata, qp.inserted_at, qp.updated_at
      FROM quest_progress qp JOIN quests q ON q.key = qp.quest_key
      WHERE q.category = 'achievement' AND qp.period_key = 'static'
      """)
    else
      execute("""
      INSERT INTO achievements (id, slug, title, description, icon_url, points, sort_order,
                                hidden, progress_target, metadata, inserted_at, updated_at)
      SELECT id, key, title, description, icon_url, 0, sort_order, hidden,
             COALESCE(json_extract(objectives, '$[0].target'), 1), metadata, inserted_at, updated_at
      FROM quests WHERE category = 'achievement'
      """)

      execute("""
      INSERT INTO user_achievements (id, user_id, achievement_id, progress, unlocked_at,
                                     metadata, inserted_at, updated_at)
      SELECT qp.id, qp.user_id, q.id, COALESCE(json_extract(qp.objective_progress, '$."0"'), 0),
             qp.completed_at, qp.metadata, qp.inserted_at, qp.updated_at
      FROM quest_progress qp JOIN quests q ON q.key = qp.quest_key
      WHERE q.category = 'achievement' AND qp.period_key = 'static'
      """)
    end
  end

  defp postgres?, do: repo().__adapter__() == Ecto.Adapters.Postgres
end
