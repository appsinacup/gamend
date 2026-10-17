defmodule Gamend.Quests.QuestProgress do
  @moduledoc """
  Ecto schema for the `quest_progress` table — one row per user, quest and
  reset period.

  ## Fields

  - `period_key` — reset bucket: a date (`"2026-07-22"`, UTC or the
    player's own, `:quest_clock`) for a daily,
    an ISO week (`"2026-W30"`) for a weekly, `"static"` otherwise. Rolling
    the period is what "resets" a quest — a new period means a fresh row.
  - `objective_progress` — map of objective index (as a string) to count
  - `status` — `"active"` → `"completed"` (all targets met) → `"claimed"`
  - `rewards_granted_at` — set once every reward entry has been applied;
    `claimed` rows without it are retried by the reward-recovery sweep
  """

  use Gamend.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(active completed claimed)

  @derive {Jason.Encoder,
           only: [
             :id,
             :user_id,
             :quest_key,
             :period_key,
             :objective_progress,
             :status,
             :completed_at,
             :claimed_at,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  schema "quest_progress" do
    belongs_to :user, Gamend.Accounts.User

    belongs_to :quest, Gamend.Quests.Quest,
      foreign_key: :quest_key,
      references: :key,
      type: :string

    field :period_key, :string, default: "static"
    field :objective_progress, :map, default: %{}
    field :status, :string, default: "active"
    field :completed_at, :utc_datetime
    field :claimed_at, :utc_datetime
    field :rewards_granted_at, :utc_datetime
    # Claims so far on THIS row. Only a `repeat` quest ever exceeds 1; it is
    # what keeps each re-armed claim's reward idempotency key distinct.
    field :claim_count, :integer, default: 0
    # Optimistic lock. Deliberately not cast: `Ecto.Changeset.optimistic_lock/2`
    # sets it, and a caller able to choose the version could defeat the check
    # that keeps two concurrent objective merges from losing one another.
    field :lock_version, :integer, default: 1
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc "The valid progress statuses."
  def statuses, do: @statuses

  @doc false
  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [
      :user_id,
      :quest_key,
      :period_key,
      :objective_progress,
      :status,
      :completed_at,
      :claimed_at,
      :rewards_granted_at,
      :claim_count,
      :metadata
    ])
    |> validate_required([:user_id, :quest_key, :period_key])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:quest_key)
    |> unique_constraint([:user_id, :quest_key, :period_key])
  end
end
