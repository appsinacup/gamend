defmodule GameServer.Quests.QuestProgress do
  @moduledoc """
  Quest progress struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Progress row ID (UUID string)
  - `user_id` - The user (UUID string)
  - `quest_key` - The quest definition's key (string)
  - `period_key` - Reset bucket: `"2026-07-22"` (daily), `"2026-W30"` (weekly) or `"static"`
  - `objective_progress` - Map of objective index (string) to count
  - `status` - `"active" | "completed" | "claimed"`
  - `completed_at` - When every objective met its target (DateTime or nil)
  - `claimed_at` - When rewards were claimed (DateTime or nil)
  - `rewards_granted_at` - When every reward entry finished granting (DateTime or nil)
  - `metadata` - Arbitrary metadata (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          quest_key: String.t(),
          period_key: String.t(),
          objective_progress: %{String.t() => non_neg_integer()},
          status: String.t(),
          completed_at: DateTime.t() | nil,
          claimed_at: DateTime.t() | nil,
          rewards_granted_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :user_id,
    :quest_key,
    :period_key,
    :objective_progress,
    :status,
    :completed_at,
    :claimed_at,
    :rewards_granted_at,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
