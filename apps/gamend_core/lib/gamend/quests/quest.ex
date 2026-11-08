defmodule Gamend.Quests.Quest do
  @moduledoc """
  Ecto schema for the `quests` table.

  Three independent dimensions, so any combination is expressible:

  - **`reset`** — when progress starts over: `"never"` (permanent, e.g. an
    achievement), `"daily"`, `"weekly"`, `"monthly"`, or `"interval"` with
    `reset_interval_days` (biweekly = 14, or any cadence).
  - **`starts_at`/`ends_at`** — an availability window ("event" quests). Works
    with any reset, so a daily can run only during a seasonal window.
  - **`prerequisite_quest_key`** — must be completed first ("chains"). Works
    with any reset, so dailies and events can chain too.

  ## Fields

  - `key` — unique slug (e.g. "daily_win_3"); progress rows reference it
  - `objectives` — list of `Gamend.Quests.Objective` (event/target/params)
  - `rewards` — list of `Gamend.Quests.Reward`, paid exactly-once
  - `auto_claim` — grant rewards on completion without a claim step
  - `hidden` — details withheld until earned (a teaser); the row still lists
  - `active` — inactive quests never advance and are not listed

  ## Grouping, which has three unrelated forms

  - **`category`** — a label your UI filters or tabs by. No engine behavior;
    every quest in a category still lists as its own row.
  - **`group_key`** (+ `group_title`, naming the collapsed entry) — many quests,
    one list entry the player opens. Unordered: every member is live at once and
    the entry stands for whichever is most worth acting on (52 countries to
    chart, in any order).
  - **`prerequisite_quest_key`** — a chain. Also one entry, but because the
    tiers are *ordered* and only one is reachable at a time.

  A quest may carry both a category and a group key. A chain inside a group
  collapses as a chain first, then contributes its surviving entry to the group.
  """

  use Gamend.Schema
  import Ecto.Changeset
  import Gamend.Limits, only: [validate_metadata_size: 2]

  alias Gamend.Quests.Objective
  alias Gamend.Quests.Reward

  require Gamend.Quests.QuestReset, as: QuestReset

  @type t :: %__MODULE__{}

  # `repeat` re-arms the moment its reward is claimed rather than waiting for a
  # clock: available again immediately, as many times as the player can finish
  # it. For an endless objective — find the treasure, then the next one — a
  # calendar reset would cap the payout at once per period.
  @resets ~w(never daily weekly monthly interval repeat)

  schema "quests" do
    field :key, :string
    field :title, :string
    field :description, :string, default: ""
    field :icon_url, :string
    field :sort_order, :integer, default: 0
    field :hidden, :boolean, default: false
    field :group_key, :string
    # Names the collapsed entry, so every member of a group declares the same one.
    field :group_title, :string
    field :reset, :string, default: QuestReset.never()
    field :reset_interval_days, :integer
    field :category, :string

    embeds_many :objectives, Objective, on_replace: :delete
    embeds_many :rewards, Reward, on_replace: :delete

    field :auto_claim, :boolean, default: false
    field :prerequisite_quest_key, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :active, :boolean, default: true
    field :metadata, :map, default: %{}

    # Which run of a `repeat` quest the player is on, for the `%{n}` in the
    # title. Virtual because it is per-player: the definition is global, so the
    # number can only exist on a row paired with a player's progress.
    # `Gamend.Quests.resolve_counter/2` sets it; nil means "no player context",
    # which reads as run 1. It is deliberately NOT written into the title —
    # that would destroy the msgid the translation is looked up by.
    field :counter, :integer, virtual: true

    has_many :progress, Gamend.Quests.QuestProgress,
      foreign_key: :quest_key,
      references: :key

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(key title)a
  @optional_fields ~w(description icon_url sort_order hidden group_key group_title
                      reset reset_interval_days category auto_claim
                      prerequisite_quest_key starts_at ends_at active metadata)a

  @doc "The valid reset cycles."
  def resets, do: @resets

  @doc false
  def changeset(quest, attrs) do
    quest
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_embed(:objectives, required: true)
    |> cast_embed(:rewards)
    |> validate_required(@required_fields)
    |> validate_length(:key, min: 1, max: Gamend.Limits.get(:max_quest_key))
    |> validate_format(:key, ~r/^[a-z0-9][a-z0-9_-]*$/,
      message: "must be lowercase letters, digits, _ or -"
    )
    |> validate_length(:title, max: Gamend.Limits.get(:max_quest_title))
    |> validate_length(:description, max: Gamend.Limits.get(:max_quest_description))
    |> validate_inclusion(:reset, @resets)
    |> validate_interval()
    |> validate_length(:category, max: Gamend.Limits.get(:max_quest_category))
    |> validate_length(:group_key, max: Gamend.Limits.get(:max_quest_category))
    |> validate_length(:group_title, max: Gamend.Limits.get(:max_quest_title))
    |> validate_objective_count()
    |> validate_reward_count()
    |> validate_window()
    |> validate_no_self_prerequisite()
    |> validate_metadata_size(:metadata)
    |> unique_constraint(:key)
  end

  # An "interval" reset is meaningless without its cadence; other resets must
  # not carry a stray one.
  defp validate_interval(changeset) do
    case {get_field(changeset, :reset), get_field(changeset, :reset_interval_days)} do
      {QuestReset.interval(), days} when is_integer(days) and days > 0 ->
        changeset

      {QuestReset.interval(), _} ->
        add_error(changeset, :reset_interval_days, "is required when reset is \"interval\"")

      {_reset, nil} ->
        changeset

      {_reset, _days} ->
        add_error(changeset, :reset_interval_days, "only applies when reset is \"interval\"")
    end
  end

  defp validate_objective_count(changeset) do
    max = Gamend.Limits.get(:max_objectives_per_quest)

    validate_change(changeset, :objectives, fn :objectives, objectives ->
      if length(objectives) > max,
        do: [objectives: "cannot have more than #{max} objectives"],
        else: []
    end)
  end

  defp validate_reward_count(changeset) do
    max = Gamend.Limits.get(:max_quest_reward_entries)

    validate_change(changeset, :rewards, fn :rewards, rewards ->
      if length(rewards) > max,
        do: [rewards: "cannot have more than #{max} reward entries"],
        else: []
    end)
  end

  defp validate_window(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(starts_at, ends_at) != :lt do
      add_error(changeset, :ends_at, "must be after starts_at")
    else
      changeset
    end
  end

  defp validate_no_self_prerequisite(changeset) do
    key = get_field(changeset, :key)

    if key && get_field(changeset, :prerequisite_quest_key) == key do
      add_error(changeset, :prerequisite_quest_key, "cannot require itself")
    else
      changeset
    end
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# Gamend.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: Gamend.Quests.Quest do
  def encode(quest, opts) do
    Gamend.SchemaJSON.encode(
      quest,
      [
        :id,
        :key,
        :title,
        :description,
        :icon_url,
        :sort_order,
        :hidden,
        :reset,
        :reset_interval_days,
        :category,
        :objectives,
        :rewards,
        :auto_claim,
        :prerequisite_quest_key,
        :starts_at,
        :ends_at,
        :active,
        :metadata,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
