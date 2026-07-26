defmodule GameServer.Leaderboards.Leaderboard do
  @moduledoc """
  Leaderboard struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Leaderboard ID (integer)
  - `slug` - URL-friendly identifier that can be reused across seasons (string)
  - `title` - Display title (string)
  - `description` - Optional description (string)
  - `icon_url` - Optional icon URL; nil means clients show their type default
  - `sort_order` - `:desc` (higher is better) or `:asc` (lower is better)
  - `operator` - Score update mode: `:set`, `:best`, `:incr`, `:decr`
  - `starts_at` - Optional start time (DateTime)
  - `ends_at` - Optional end time (DateTime)
  - `metadata` - Arbitrary metadata (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type sort_order :: :desc | :asc
  @type operator :: :set | :best | :incr | :decr

  @type t :: %__MODULE__{
          id: integer(),
          slug: String.t(),
          title: String.t(),
          description: String.t() | nil,
          icon_url: String.t() | nil,
          sort_order: sort_order(),
          operator: operator(),
          starts_at: DateTime.t() | nil,
          ends_at: DateTime.t() | nil,
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
    :sort_order,
    :operator,
    :starts_at,
    :ends_at,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
