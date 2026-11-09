defmodule Gamend.Quests.QuestCode do
  @moduledoc """
  Redemption code struct from Gamend.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Code ID (UUID string)
  - `quest_key` - The code-only quest it finishes (string)
  - `token` - The code as people see it (string)
  - `lookup` - The token normalized, what a redeem compares (string)
  - `max_uses` - `1` single-use, `N` the first N players, `nil` every player once
  - `uses` - How many players redeemed it (integer)
  - `status` - `"active" | "revoked"`
  - `metadata` - Copied onto each player's progress row (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          quest_key: String.t(),
          token: String.t(),
          lookup: String.t(),
          max_uses: pos_integer() | nil,
          uses: non_neg_integer(),
          status: String.t(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :quest_key,
    :token,
    :lookup,
    :max_uses,
    :uses,
    :status,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
