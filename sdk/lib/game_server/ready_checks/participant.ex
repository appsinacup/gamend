defmodule GameServer.ReadyChecks.Participant do
  @moduledoc """
  Ready check participant struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Participant ID (string)
  - `ready_check_id` - The check this answer belongs to (string)
  - `user_id` - Who is answering (string)
  - `ticket_id` - Their matchmaking ticket (string, nil for a lobby check)
  - `state` - `"pending"`, `"ready"`, `"declined"` or `"timed_out"`
  - `responded_at` - When they answered (nil while pending)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          ready_check_id: String.t(),
          user_id: String.t(),
          ticket_id: String.t() | nil,
          state: String.t(),
          responded_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :ready_check_id,
    :user_id,
    :ticket_id,
    :state,
    :responded_at,
    :inserted_at,
    :updated_at
  ]
end
