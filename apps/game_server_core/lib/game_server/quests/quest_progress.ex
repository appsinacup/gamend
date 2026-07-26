defmodule GameServer.Quests.QuestProgress do
  @moduledoc """
  Ecto schema for the `quest_progress` table — one row per user, quest and
  reset period.

  ## Fields

  - `period_key` — reset bucket: a UTC date (`"2026-07-22"`) for a daily,
    an ISO week (`"2026-W30"`) for a weekly, `"static"` otherwise. Rolling
    the period is what "resets" a quest — a new period means a fresh row.
  - `objective_progress` — map of objective index (as a string) to count
  - `status` — `"active"` → `"completed"` (all targets met) → `"claimed"`
  - `rewards_granted_at` — set once every reward entry has been applied;
    `claimed` rows without it are retried by the reward-recovery sweep
  """

  use GameServer.Schema
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
    belongs_to :user, GameServer.Accounts.User

    belongs_to :quest, GameServer.Quests.Quest,
      foreign_key: :quest_key,
      references: :key,
      type: :string

    field :period_key, :string, default: "static"
    field :objective_progress, :map, default: %{}
    field :status, :string, default: "active"
    field :completed_at, :utc_datetime
    field :claimed_at, :utc_datetime
    field :rewards_granted_at, :utc_datetime
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
      :metadata
    ])
    |> validate_required([:user_id, :quest_key, :period_key])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:quest_key)
    |> unique_constraint([:user_id, :quest_key, :period_key])
  end
end
