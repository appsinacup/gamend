defmodule GamendWeb.Schemas.Friend do
  @moduledoc "A friend: the member-list row plus the friendship's id, which the friend actions take."
  require OpenApiSpex
  alias GamendWeb.Schemas.{FreeForm, PlayerCard}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Friend",
    description: "An accepted friend",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "The friend's user id"},
      friendship_id: %Schema{
        type: :string,
        format: :uuid,
        description: "The friendship row: the id remove, block and unblock take"
      },
      username: %Schema{type: :string},
      display_name: %Schema{type: :string},
      profile_url: %Schema{type: :string},
      metadata: FreeForm.metadata(),
      is_online: %Schema{type: :boolean},
      is_activated: %Schema{type: :boolean},
      last_seen_at: %Schema{type: :string, format: :"date-time"},
      card: PlayerCard
    },
    required: [
      :id,
      :friendship_id,
      :username,
      :display_name,
      :profile_url,
      :metadata,
      :is_online,
      :is_activated,
      :last_seen_at,
      :card
    ]
  })
end

defmodule GamendWeb.Schemas.FriendPage do
  @moduledoc "A page of friends."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Friend
end

defmodule GamendWeb.Schemas.FriendRequest do
  @moduledoc "A pending friendship row, with both users and their player cards."
  require OpenApiSpex
  alias GamendWeb.Schemas.UserCard
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "FriendRequest",
    description: "A friend request",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "The friendship row id"},
      requester: UserCard,
      target: UserCard,
      status: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :requester, :target, :status, :inserted_at]
  })
end

defmodule GamendWeb.Schemas.FriendRequestLists do
  @moduledoc "Incoming and outgoing requests, each paged on its own."
  require OpenApiSpex
  alias GamendWeb.Schemas.FriendRequest
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "FriendRequestLists",
    description: "Requests to and from the user",
    type: :object,
    properties: %{
      incoming: %Schema{type: :array, items: FriendRequest},
      outgoing: %Schema{type: :array, items: FriendRequest}
    },
    required: [:incoming, :outgoing]
  })
end

defmodule GamendWeb.Schemas.FriendRequestMeta do
  @moduledoc "One `PageMeta` per request list."
  require OpenApiSpex
  alias GamendWeb.Schemas.PageMeta

  OpenApiSpex.schema(%{
    title: "FriendRequestMeta",
    description: "Pagination for each request list",
    type: :object,
    properties: %{incoming: PageMeta, outgoing: PageMeta},
    required: [:incoming, :outgoing]
  })
end

defmodule GamendWeb.Schemas.FriendRequestsResponse do
  @moduledoc "Both request lists under `data`, their pagination under `meta`."
  use GamendWeb.Schemas.Envelope,
    data: GamendWeb.Schemas.FriendRequestLists,
    extra: %{meta: GamendWeb.Schemas.FriendRequestMeta},
    required: [:meta]
end

defmodule GamendWeb.Schemas.BlockedFriendship do
  @moduledoc "A friendship the user blocked, with the blocked user."
  require OpenApiSpex
  alias GamendWeb.Schemas.UserBrief
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "BlockedFriendship",
    description: "A blocked friendship row",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "The friendship row id"},
      requester: UserBrief
    },
    required: [:id, :requester]
  })
end

defmodule GamendWeb.Schemas.BlockedFriendshipPage do
  @moduledoc "A page of blocked friendships."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.BlockedFriendship
end

defmodule GamendWeb.Schemas.FriendRequestResponse do
  @moduledoc "One friend request under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.FriendRequest
end
