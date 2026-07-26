defmodule GameServer.Quests.Quest do
  @moduledoc """
  Quest definition struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Quest ID (UUID string)
  - `key` - Unique slug (string)
  - `title` - Display title (string)
  - `description` - Optional description (string)
  - `icon_url` - Optional icon URL (string)
  - `sort_order` - Display ordering (integer, default 0)
  - `hidden` - Whether hidden until completed (boolean)
  - `kind` - `"achievement" | "daily" | "weekly" | "event" | "chain"`
  - `objectives` - List of `GameServer.Quests.Objective`
  - `rewards` - List of `GameServer.Quests.Reward`
  - `auto_claim` - Grant rewards on completion without a claim step (boolean)
  - `prerequisite_quest_key` - Key of the quest gating this one (string or nil)
  - `starts_at` / `ends_at` - Event-quest window (DateTime or nil)
  - `active` - Inactive quests never advance and are not listed (boolean)
  - `metadata` - Arbitrary metadata (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          key: String.t(),
          title: String.t(),
          description: String.t() | nil,
          icon_url: String.t() | nil,
          sort_order: integer(),
          hidden: boolean(),
          kind: String.t(),
          objectives: [GameServer.Quests.Objective.t()],
          rewards: [GameServer.Quests.Reward.t()],
          auto_claim: boolean(),
          prerequisite_quest_key: String.t() | nil,
          starts_at: DateTime.t() | nil,
          ends_at: DateTime.t() | nil,
          active: boolean(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :key,
    :title,
    :description,
    :icon_url,
    :sort_order,
    :hidden,
    :kind,
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
  ]
end
