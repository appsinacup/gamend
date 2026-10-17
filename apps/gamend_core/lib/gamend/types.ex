defmodule Gamend.Types do
  @moduledoc """
  Shared types used across Gamend contexts.

  These types provide self-documenting function signatures for common
  patterns like pagination options and entity attributes.
  """

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  @typedoc """
  Pagination options for list queries.

  ## Options

    * `:page` - The page number (1-indexed). Defaults to `1`.
    * `:page_size` - Number of items per page. Defaults to `25`.

  ## Example

      # Get the first page with default size
      list_users([])

      # Get page 2 with 50 items per page
      list_users(page: 2, page_size: 50)

  """
  @type pagination_opts :: [page: pos_integer(), page_size: pos_integer()]

  @typedoc """
  Lobby listing options for filtering and pagination.

  ## Options

    * `:page` - The page number (1-indexed). Defaults to `nil` (returns all).
    * `:page_size` - Number of items per page. Defaults to `25`.
    * `:include_hidden` - Include hidden lobbies in results. Defaults to `false`.

  ## Example

      # List all visible lobbies
      list_lobbies([])

      # List page 1 including hidden lobbies
      list_lobbies(page: 1, include_hidden: true)

  """
  @type lobby_list_opts :: [
          page: pos_integer() | nil,
          page_size: pos_integer(),
          include_hidden: boolean()
        ]

  # ---------------------------------------------------------------------------
  # User Attributes
  # ---------------------------------------------------------------------------

  @typedoc """
  Attributes for registering a new user.

  ## Fields

    * `:email` - User's email address (required for email registration)
    * `:password` - User's password (required for email registration, min 8 chars)
    * `:display_name` - Optional display name
    * `:device_id` - Optional device ID for anonymous auth

  ## Example

      register_user(%{
        email: "user@example.com",
        password: "secret123",
        display_name: "Player One"
      })

  """
  @type user_registration_attrs :: %{
          optional(:email) => String.t(),
          optional(:password) => String.t(),
          optional(:username) => String.t(),
          optional(:display_name) => String.t(),
          optional(:device_id) => String.t()
        }

  @typedoc """
  String-keyed registration attrs flowing through the `before_user_register`
  hook pipeline.

  Always contains the generated `"username"`; the remaining keys depend on the
  signup source — `"email"`, `"display_name"`, `"metadata"`, and provider id
  fields such as `"google_id"` or `"device_id"`.
  """
  @type user_registration_hook_attrs :: %{optional(String.t()) => term()}

  @typedoc """
  Attributes for updating an existing user.

  ## Fields

    * `:display_name` - User's display name
    * `:metadata` - Arbitrary key-value data stored with the user
    * `:is_admin` - Whether the user has admin privileges

  ## Example

      update_user(user, %{
        display_name: "New Name",
        metadata: %{level: 5, xp: 1200}
      })

  """
  @type user_update_attrs :: %{optional(atom() | String.t()) => term()}

  # ---------------------------------------------------------------------------
  # Leaderboard Attributes
  # ---------------------------------------------------------------------------

  @typedoc """
  Attributes for creating a new leaderboard.

  ## Fields

    * `:slug` - Human-readable identifier (required, 1-100 chars, lowercase alphanumeric with underscores)
    * `:title` - Display title (required, 1-255 chars)
    * `:description` - Optional description
    * `:sort_order` - `:desc` (higher is better) or `:asc` (lower is better). Default: `:desc`
    * `:operator` - How scores are combined:
      * `:set` - Always replace with new score
      * `:best` - Only update if new score is better (default)
      * `:incr` - Add to existing score
      * `:decr` - Subtract from existing score
    * `:starts_at` - Optional start time (UTC)
    * `:ends_at` - Optional end time (UTC)
    * `:metadata` - Arbitrary key-value data
    * `:hidden` - Left out of every public listing (default false)

  ## Example

      create_leaderboard(%{
        slug: "weekly_kills",
        title: "Weekly Kills",
        sort_order: :desc,
        operator: :incr,
        ends_at: ~U[2024-12-08 00:00:00Z]
      })

  Note: The same slug can be used for multiple leaderboards (seasons).
  When querying by slug, the active leaderboard is returned.
  """
  @type leaderboard_create_attrs :: %{
          required(:slug) => String.t(),
          required(:title) => String.t(),
          optional(:description) => String.t(),
          # In the schema and cast by the changeset, but missing here, so every
          # caller passing an icon read as a call that could not succeed.
          optional(:icon_url) => String.t(),
          optional(:sort_order) => :desc | :asc,
          optional(:operator) => :set | :best | :incr | :decr,
          optional(:starts_at) => DateTime.t(),
          optional(:ends_at) => DateTime.t(),
          optional(:metadata) => map(),
          optional(:hidden) => boolean()
        }

  @typedoc """
  Attributes for updating an existing leaderboard.

  Note: `slug`, `sort_order`, and `operator` cannot be changed after creation.

  ## Fields

    * `:title` - Display title (1-255 chars)
    * `:description` - Description text
    * `:starts_at` - Start time (UTC)
    * `:ends_at` - End time (UTC)
    * `:metadata` - Arbitrary key-value data
    * `:hidden` - Left out of every public listing (default false)

  ## Example

      update_leaderboard(leaderboard, %{
        title: "Updated Title",
        ends_at: ~U[2024-12-15 00:00:00Z]
      })

  """
  @type leaderboard_update_attrs :: %{
          optional(:title) => String.t(),
          optional(:description) => String.t(),
          optional(:starts_at) => DateTime.t(),
          optional(:ends_at) => DateTime.t(),
          optional(:metadata) => map(),
          optional(:hidden) => boolean()
        }

  # ---------------------------------------------------------------------------
  # Lobby Attributes
  # ---------------------------------------------------------------------------

  @typedoc """
  Attributes for creating a new lobby.

  ## Fields

    * `:name` - Unique identifier/slug (required)
    * `:title` - Display title (required)
    * `:max_users` - Maximum number of users allowed (default: 10)
    * `:is_hidden` - Whether lobby is hidden from public lists (default: false)
    * `:is_locked` - Whether lobby is locked from new joins (default: false)
    * `:password` - Optional password for protected lobbies
    * `:hostless` - Whether lobby can exist without a host (default: false)
    * `:metadata` - Arbitrary key-value data

  ## Example

      create_lobby(user, %{
        name: "my-game-room",
        title: "My Game Room",
        max_users: 4,
        password: "secret"
      })

  """
  @type lobby_create_attrs :: %{optional(atom() | String.t()) => term()}

  @typedoc """
  Attributes for updating an existing lobby.

  ## Fields

    * `:title` - Display title
    * `:max_users` - Maximum number of users allowed
    * `:is_hidden` - Whether lobby is hidden from public lists
    * `:is_locked` - Whether lobby is locked from new joins
    * `:password` - Password for protected lobbies (set to nil to remove)
    * `:metadata` - Arbitrary key-value data

  ## Example

      update_lobby(lobby, user, %{
        title: "New Title",
        is_locked: true
      })

  """
  @type lobby_update_attrs :: %{
          optional(:title) => String.t(),
          optional(:max_users) => pos_integer(),
          optional(:is_hidden) => boolean(),
          optional(:is_locked) => boolean(),
          optional(:password) => String.t() | nil,
          optional(:metadata) => map()
        }

  # ---------------------------------------------------------------------------
  # Group Attributes
  # ---------------------------------------------------------------------------

  @typedoc """
  Attributes for creating a new group.

  ## Fields

    * `:name` - Unique slug / identifier (required, 1-80 chars)
    * `:title` - Display title (required, 1-80 chars)
    * `:description` - Optional description (max 500 chars)
    * `:type` - Visibility: `"public"`, `"private"`, or `"hidden"` (default: `"public"`)
    * `:max_members` - Maximum members allowed (default: 100, max: 10000)
    * `:metadata` - Server-managed arbitrary key-value data

  ## Example

      create_group(user_id, %{
        name: "my-guild",
        title: "My Guild",
        type: "public",
        max_members: 50,
        metadata: %{"lang_tag" => "en"}
      })

  """
  @type group_create_attrs :: %{
          required(:name) => String.t(),
          required(:title) => String.t(),
          optional(:description) => String.t(),
          optional(:type) => String.t(),
          optional(:max_members) => pos_integer(),
          optional(:metadata) => map()
        }

  @typedoc """
  Attributes for updating an existing group.

  ## Fields

    * `:title` - Display title
    * `:description` - Description
    * `:type` - Visibility type
    * `:max_members` - Max members (cannot be less than current member count)
    * `:metadata` - Server-managed metadata

  ## Example

      update_group(admin_id, group_id, %{
        title: "New Title",
        max_members: 200
      })

  """
  @type group_update_attrs :: %{
          optional(:title) => String.t(),
          optional(:description) => String.t(),
          optional(:type) => String.t(),
          optional(:max_members) => pos_integer(),
          optional(:metadata) => map()
        }

  # ---------------------------------------------------------------------------
  # Matchmaking Attributes
  # ---------------------------------------------------------------------------

  @typedoc """
  A matchmaking ticket as returned by the database.

  ## Fields

    * `:id` - Ticket ID
    * `:user_id` - ID of the queued user
    * `:status` - Current status (`"queued"`, `"matched"` or `"cancelled"`)
    * `:match_params` - Arbitrary parameters used for grouping tickets
    * `:min_players` - Minimum players required for a match
    * `:max_players` - Maximum players allowed for a match
    * `:timeout_ms` - Maximum wait time before forcing a match
    * `:queued_at` - When the ticket was created
    * `:matched_at` - When the ticket was matched
    * `:match_id` - ID of the lobby the ticket was matched to
  """
  @type matchmaking_ticket :: %{
          required(:id) => Ecto.UUID.t(),
          required(:user_id) => Ecto.UUID.t(),
          required(:status) => String.t(),
          required(:match_params) => %{String.t() => String.t()},
          required(:min_players) => pos_integer(),
          required(:max_players) => pos_integer(),
          required(:timeout_ms) => pos_integer(),
          required(:queued_at) => DateTime.t(),
          optional(:matched_at) => DateTime.t() | nil,
          optional(:match_id) => Ecto.UUID.t() | nil
        }
end
