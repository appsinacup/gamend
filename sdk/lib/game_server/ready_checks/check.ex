defmodule GameServer.ReadyChecks.Check do
  @moduledoc """
  Ready check struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Check ID (string)
  - `kind` - `"ready"` (lobby ready-up) or `"accept"` (match confirmation)
  - `status` - `"pending"`, `"passed"`, `"failed"` or `"cancelled"`
  - `lobby_id` - Lobby the check belongs to (string, nil for a matchmaking check)
  - `deadline_at` - When unanswered participants time out (nil for an open-ended ready check)
  - `opened_by` - User who opened it (string, nil when the server did)
  - `reason` - Why it failed: `"declined"`, `"timeout"` or `"cancelled"` (nil while pending)
  - `resolved_at` - When it stopped being pending
  - `metadata` - Arbitrary payload echoed to clients (map)
  - `participants` - The answers (list of `GameServer.ReadyChecks.Participant`)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          kind: String.t(),
          status: String.t(),
          lobby_id: String.t() | nil,
          deadline_at: DateTime.t() | nil,
          opened_by: String.t() | nil,
          reason: String.t() | nil,
          resolved_at: DateTime.t() | nil,
          metadata: map(),
          participants: list(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :kind,
    :status,
    :lobby_id,
    :deadline_at,
    :opened_by,
    :reason,
    :resolved_at,
    :metadata,
    :participants,
    :inserted_at,
    :updated_at
  ]
end
