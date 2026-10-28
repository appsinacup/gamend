defmodule Gamend.Groups.Group do
  @moduledoc """
  Group struct from Gamend.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Group ID (integer)
  - `title` - Group title (string)
  - `slug` - Its name in a URL, unique per creator (string); `Gamend.Groups.full_slug/1` is `<owner>/<slug>`
  - `description` - Group description (string)
  - `icon_url` - Optional icon URL; nil means clients show their type default
  - `type` - Group type: `"public"`, `"private"`, or `"hidden"` (string)
  - `max_members` - Maximum number of members (integer, default 100)
  - `metadata` - Arbitrary group metadata (map)
  - `slowdown` - Rate-limit slowdown in milliseconds (integer, default 0)
  - `creator_id` - ID of the user who created the group (integer)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: integer(),
          title: String.t(),
          slug: String.t(),
          description: String.t(),
          icon_url: String.t() | nil,
          type: String.t(),
          max_members: integer(),
          metadata: map(),
          slowdown: integer(),
          creator_id: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :title,
    :slug,
    :description,
    :icon_url,
    :type,
    :max_members,
    :metadata,
    :slowdown,
    :creator_id,
    :inserted_at,
    :updated_at
  ]
end
