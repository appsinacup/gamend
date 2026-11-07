defmodule GamendWeb.Schemas.LinkedProviders do
  @moduledoc "Which sign-in methods an account has, as `Accounts.get_linked_providers/1` reports them."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LinkedProviders",
    description: "Which sign-in methods are linked to the account",
    type: :object,
    properties: %{
      google: %Schema{type: :boolean},
      facebook: %Schema{type: :boolean},
      github: %Schema{type: :boolean},
      discord: %Schema{type: :boolean},
      apple: %Schema{type: :boolean},
      steam: %Schema{type: :boolean},
      device: %Schema{type: :boolean}
    },
    required: [:google, :facebook, :github, :discord, :apple, :steam, :device]
  })
end

defmodule GamendWeb.Schemas.AccountBan do
  @moduledoc "A ban on the signed-in account, as `GET /me` sends it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AccountBan",
    description:
      "The account is banned: it can read and delete itself, every other call answers 403 `account_banned`",
    type: :object,
    properties: %{
      expires_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When the ban ends; null for a permanent ban"
      },
      reason: %Schema{type: :string, description: "Why, for the player; may be empty"}
    },
    required: [:expires_at, :reason]
  })
end

defmodule GamendWeb.Schemas.CurrentUser do
  @moduledoc "The signed-in user, as `GET /me` sends it: the only user shape carrying email."
  require OpenApiSpex
  alias GamendWeb.Schemas.LinkedProviders
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CurrentUser",
    description: "The authenticated user",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      email: %Schema{type: :string, description: "Empty for accounts without one"},
      profile_url: %Schema{
        type: :string,
        description:
          "The avatar: an image we host, or one of the server's icons (`/icons/<name>.svg?color=<color>`), one the user's id gives them when they set none"
      },
      username: %Schema{type: :string, description: "Unique handle"},
      display_name: %Schema{type: :string, description: "Chosen name"},
      metadata: %Schema{type: :object},
      lobby_id: %Schema{type: :string, description: "Current lobby id, or empty"},
      party_id: %Schema{type: :string, description: "Current party id, or empty"},
      is_online: %Schema{type: :boolean},
      last_seen_at: %Schema{type: :string, format: :"date-time"},
      linked_providers: LinkedProviders,
      has_password: %Schema{type: :boolean, description: "Whether a password is set"},
      ban: %Schema{
        allOf: [GamendWeb.Schemas.AccountBan],
        nullable: true,
        description: "The account's ban while it is banned, else null"
      }
    },
    required: [
      :id,
      :email,
      :profile_url,
      :username,
      :display_name,
      :metadata,
      :lobby_id,
      :party_id,
      :is_online,
      :last_seen_at,
      :linked_providers,
      :has_password,
      :ban
    ]
  })
end

defmodule GamendWeb.Schemas.PublicUser do
  @moduledoc """
  Another user, as `GET /users` and `GET /users/:id` send them: the member-list
  row without the avatar, with metadata cut to the public keys.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PublicUser",
    description: "A user as anyone may see them",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      username: %Schema{type: :string, description: "Unique handle"},
      display_name: %Schema{type: :string, description: "Chosen name"},
      metadata: %Schema{
        type: :object,
        description:
          "User metadata, restricted to the keys named by the :public_user_metadata_keys setting. Empty by default."
      },
      is_online: %Schema{type: :boolean},
      is_activated: %Schema{type: :boolean},
      last_seen_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :username,
      :display_name,
      :metadata,
      :is_online,
      :is_activated,
      :last_seen_at
    ]
  })
end

defmodule GamendWeb.Schemas.PublicUserPage do
  @moduledoc "A page of users from a search."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.PublicUser
end

defmodule GamendWeb.Schemas.PlayerStats do
  @moduledoc "The counters `Gamend.Accounts.player_stats/0` returns."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayerStats",
    description: "Player counts, cached for up to a minute",
    type: :object,
    properties: %{
      players_online: %Schema{type: :integer},
      players_total: %Schema{type: :integer},
      players_offline: %Schema{type: :integer},
      players_in_lobbies: %Schema{type: :integer},
      players_in_parties: %Schema{type: :integer}
    },
    required: [
      :players_online,
      :players_total,
      :players_offline,
      :players_in_lobbies,
      :players_in_parties
    ]
  })
end

defmodule GamendWeb.Schemas.PlayerStatsResponse do
  @moduledoc "Player counts under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PlayerStats
end

defmodule GamendWeb.Schemas.CurrentUserResponse do
  @moduledoc "The signed-in user under `data`; every profile change answers it."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.CurrentUser
end

defmodule GamendWeb.Schemas.PublicUserResponse do
  @moduledoc "One user under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PublicUser
end
