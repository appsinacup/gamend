defmodule GamendWeb.Schemas.PlayerCard do
  @moduledoc """
  What the site's player card draws about a user beside their name and
  avatar (`GamendWeb.Serializers.player_card/1`), from the host's hooks.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayerCard",
    description: "The host's line, badge and mark for a player",
    type: :object,
    properties: %{
      title: %Schema{
        type: :string,
        description:
          "The line under the name (`:user_title`), in the reader's language; empty for none"
      },
      title_class: %Schema{
        type: :string,
        description:
          "The host's class for that line (`:user_title_class`), its look; empty for none"
      },
      badge: %Schema{
        type: :string,
        description: "The tag beside the name (`:user_badge`, \"Pro\"); empty for none"
      },
      mark: %Schema{
        type: :string,
        description: "What the host draws on the avatar (`:user_mark`, a level); empty for none"
      }
    },
    required: [:title, :title_class, :badge, :mark]
  })
end

defmodule GamendWeb.Schemas.UserBrief do
  @moduledoc """
  A user as `Gamend.Accounts.User.serialize_brief/1` sends it: the compact
  row in lobby, party and friend member lists. The realtime proto's
  `UserBrief` is the same shape.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UserBrief",
    description: "A user as it appears in a member list",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      username: %Schema{type: :string, description: "Unique handle"},
      display_name: %Schema{type: :string, description: "Chosen name"},
      profile_url: %Schema{
        type: :string,
        description:
          "The avatar: an image we host, or one of the server's icons (`/icons/<name>.svg?color=<color>`), one the user's id gives them when they set none"
      },
      metadata: FreeForm.metadata(description: "Public user metadata"),
      is_online: %Schema{type: :boolean},
      is_activated: %Schema{type: :boolean},
      last_seen_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :username,
      :display_name,
      :profile_url,
      :metadata,
      :is_online,
      :is_activated,
      :last_seen_at
    ]
  })
end

defmodule GamendWeb.Schemas.UserBriefPage do
  @moduledoc "A page of users as member-list rows."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.UserBrief
end

defmodule GamendWeb.Schemas.UserCard do
  @moduledoc """
  A user as a list a player picks people from sends them: the member-list
  row (`GamendWeb.Schemas.UserBrief`) and its player card.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.{PlayerCard, UserBrief}

  brief = UserBrief.schema()

  OpenApiSpex.schema(%{
    title: "UserCard",
    description: "A user with their player card",
    type: :object,
    properties: Map.put(brief.properties, :card, PlayerCard),
    required: [:card | brief.required]
  })
end
