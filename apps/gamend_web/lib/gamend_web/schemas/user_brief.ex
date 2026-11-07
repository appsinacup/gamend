defmodule GamendWeb.Schemas.UserBrief do
  @moduledoc """
  A user as `Gamend.Accounts.User.serialize_brief/1` sends it: the compact
  row in lobby, party and friend member lists. The realtime proto's
  `UserBrief` is the same shape.
  """
  require OpenApiSpex
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
      metadata: %Schema{type: :object, description: "Public user metadata"},
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
