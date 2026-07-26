defmodule GameServer.Tournaments.Tournament do
  @moduledoc """
  Tournament struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Tournament ID (UUIDv7 string)
  - `slug` - Identifier shared by every occurrence of a recurring tournament
  - `title` - Display title (string)
  - `description` - Description (string)
  - `icon_url` - Optional icon URL; nil means clients show their type default
  - `state` - `"scheduled"`, `"registration"`, `"running"`, `"finished"` or `"cancelled"`
  - `registration_opens_at` - When registration opens (nil = open immediately)
  - `starts_at` - When the bracket is drawn (nil = started manually)
  - `ends_at` - Optional hard stop
  - `recur` - Cron expression spawning the next occurrence (nil = one-shot)
  - `max_entries` - Optional cap on registrations
  - `team_size` - Advisory; enforced by game hooks, not by the server
  - `bracket_size` - Slots per bracket (power of two); extra entries fill more brackets
  - `round_window_sec` - Play window per round
  - `deadline_policy` - Fallback when a match is unresolved at its deadline
  - `metadata` - Arbitrary metadata (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type state :: String.t()

  @type t :: %__MODULE__{
          id: String.t(),
          slug: String.t(),
          title: String.t(),
          description: String.t(),
          icon_url: String.t() | nil,
          state: state(),
          registration_opens_at: DateTime.t() | nil,
          starts_at: DateTime.t() | nil,
          ends_at: DateTime.t() | nil,
          recur: String.t() | nil,
          max_entries: integer() | nil,
          team_size: integer(),
          bracket_size: integer(),
          round_window_sec: integer(),
          deadline_policy: String.t(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :slug,
    :title,
    :description,
    :icon_url,
    :state,
    :registration_opens_at,
    :starts_at,
    :ends_at,
    :recur,
    :max_entries,
    :team_size,
    :bracket_size,
    :round_window_sec,
    :deadline_policy,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
