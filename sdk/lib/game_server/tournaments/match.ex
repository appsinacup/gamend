defmodule GameServer.Tournaments.Match do
  @moduledoc """
  Tournament match struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  A match is a pairing plus a verdict: two entries that must produce a winner
  by `deadline_at`. How it is played is up to the game — the server only needs
  `GameServer.Tournaments.resolve_match/2` called before the deadline.

  Payloads passed to `tournament_match_ready/1` and `tournament_match_expired/1`
  have `tournament`, `a_entry` and `b_entry` preloaded.

  ## Fields

  - `id` - Match ID (UUIDv7 string)
  - `tournament_id` / `tournament` - Owning tournament
  - `bracket_index` - Which bracket this match belongs to
  - `round` - 1-based round number
  - `slot` - Position within the round
  - `a_entry_id` / `a_entry` - First side (nil until its feeder resolves)
  - `b_entry_id` / `b_entry` - Second side (nil until its feeder resolves)
  - `winner_entry_id` - Set on resolution; nil with `resolved_at` set means a double forfeit
  - `ready_at` - When the match became playable
  - `expired_at` - When the deadline passed with the match still open
  - `resolved_at` - When the verdict was recorded
  - `deadline_at` - End of the round window
  - `metadata` - Game scratch space, e.g. runs or a lobby id (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          tournament_id: String.t(),
          tournament: GameServer.Tournaments.Tournament.t() | nil,
          bracket_index: integer(),
          round: integer(),
          slot: integer(),
          a_entry_id: String.t() | nil,
          b_entry_id: String.t() | nil,
          a_entry: GameServer.Tournaments.Entry.t() | nil,
          b_entry: GameServer.Tournaments.Entry.t() | nil,
          winner_entry_id: String.t() | nil,
          ready_at: DateTime.t() | nil,
          expired_at: DateTime.t() | nil,
          resolved_at: DateTime.t() | nil,
          deadline_at: DateTime.t(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :tournament_id,
    :tournament,
    :bracket_index,
    :round,
    :slot,
    :a_entry_id,
    :b_entry_id,
    :a_entry,
    :b_entry,
    :winner_entry_id,
    :ready_at,
    :expired_at,
    :resolved_at,
    :deadline_at,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
