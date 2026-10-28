defmodule GamendWeb.Schemas.Group do
  @moduledoc """
  A group as `GamendWeb.Serializers.serialize_group/2` sends it. The group
  endpoints ask for the member count, slowdown and timestamps, so those are
  declared; other callers of the serializer leave them out, so they are not
  required.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Group",
    description: "A group",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string, description: "Display title"},
      slug: %Schema{
        type: :string,
        description:
          "Its name in a URL, unique per creator: lowercase letters and digits joined by - or _"
      },
      description: %Schema{type: :string, description: "Empty when unset"},
      icon_url: %Schema{type: :string, description: "Empty when unset"},
      type: %Schema{
        type: :string,
        enum: ["public", "private", "hidden"],
        description: "Who may join and who may see it"
      },
      max_members: %Schema{type: :integer},
      metadata: %Schema{type: :object, description: "Server-managed metadata"},
      creator_id: %Schema{
        type: :string,
        description: "Creator's user id; empty for a system group"
      },
      creator_name: %Schema{type: :string, description: "Creator's display name, or empty"},
      member_count: %Schema{type: :integer},
      slowdown: %Schema{type: :integer, description: "Chat slowdown in seconds (0 = off)"},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :title,
      :slug,
      :description,
      :icon_url,
      :type,
      :max_members,
      :metadata,
      :creator_id,
      :creator_name
    ],
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      title: "Awesome Guild",
      slug: "awesome-guild",
      description: "A group for awesome players",
      icon_url: "",
      type: "public",
      max_members: 100,
      metadata: %{"lang_tag" => "en"},
      creator_id: "0198c0de-0002-7000-8000-000000000002",
      creator_name: "AwesomePlayer",
      member_count: 12,
      slowdown: 0
    }
  })
end

defmodule GamendWeb.Schemas.GroupPage do
  @moduledoc "A page of groups."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Group
end

defmodule GamendWeb.Schemas.GroupMember do
  @moduledoc """
  A membership row with its user. For a caller who is not signed in, the
  presence and avatar fields are blanked (`profile_url` empty, `is_online`
  false, `last_seen_at` the epoch) rather than left out.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GroupMember",
    description: "A member of a group",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "The membership row id"},
      user_id: %Schema{type: :string, format: :uuid},
      group_id: %Schema{type: :string, format: :uuid},
      role: %Schema{type: :string, enum: ["admin", "member"]},
      username: %Schema{type: :string},
      display_name: %Schema{type: :string},
      profile_url: %Schema{type: :string, description: "Empty when unset or signed out"},
      is_online: %Schema{type: :boolean},
      last_seen_at: %Schema{type: :string, format: :"date-time"},
      inserted_at: %Schema{type: :string, format: :"date-time", description: "When they joined"}
    },
    required: [
      :id,
      :user_id,
      :group_id,
      :role,
      :username,
      :display_name,
      :profile_url,
      :is_online,
      :last_seen_at,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.GroupMemberPage do
  @moduledoc "A page of group members."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.GroupMember
end

defmodule GamendWeb.Schemas.GroupJoinRequest do
  @moduledoc "A request to join a private group, with the requester's names."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GroupJoinRequest",
    description: "A request to join a group",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      group_id: %Schema{type: :string, format: :uuid},
      status: %Schema{type: :string, enum: ["pending", "accepted", "rejected"]},
      username: %Schema{type: :string},
      display_name: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :user_id, :group_id, :status, :username, :display_name, :inserted_at]
  })
end

defmodule GamendWeb.Schemas.GroupJoinRequestPage do
  @moduledoc "A page of join requests."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.GroupJoinRequest
end

defmodule GamendWeb.Schemas.GroupInvite do
  @moduledoc "An invitation to a group, as `Gamend.Groups` lists it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GroupInvite",
    description: "An invitation to join a group",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      group_id: %Schema{type: :string, format: :uuid},
      group_title: %Schema{type: :string},
      sender_id: %Schema{type: :string, format: :uuid},
      sender_name: %Schema{type: :string},
      recipient_id: %Schema{type: :string, format: :uuid},
      recipient_name: %Schema{type: :string},
      status: %Schema{type: :string, description: "pending | accepted | declined | cancelled"},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :group_id,
      :group_title,
      :sender_id,
      :sender_name,
      :recipient_id,
      :recipient_name,
      :status,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.GroupInvitePage do
  @moduledoc "A page of group invitations."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.GroupInvite
end

defmodule GamendWeb.Schemas.GroupResponse do
  @moduledoc "One group under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Group
end

defmodule GamendWeb.Schemas.GroupMemberResponse do
  @moduledoc "One membership under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.GroupMember
end

defmodule GamendWeb.Schemas.GroupJoinRequestResponse do
  @moduledoc "One join request under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.GroupJoinRequest
end

defmodule GamendWeb.Schemas.GroupInviteOutcome do
  @moduledoc "What inviting a user to a group did."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GroupInviteOutcome",
    description: "The result of an invitation",
    type: :object,
    properties: %{
      status: %Schema{
        type: :string,
        enum: ["invited", "request_approved"],
        description:
          "`invited` when an invite was created, `request_approved` when the user had asked to join and was let in instead"
      }
    },
    required: [:status]
  })
end

defmodule GamendWeb.Schemas.GroupInviteOutcomeResponse do
  @moduledoc "The invitation's outcome under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.GroupInviteOutcome
end

defmodule GamendWeb.Schemas.GroupInviteLink do
  @moduledoc "A group's invite link (`Gamend.Groups.InviteLinks`)."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GroupInviteLink",
    description:
      "A group's invite link: anyone signed in who opens `url`, or joins with `token`, becomes a member",
    type: :object,
    properties: %{
      group_id: %Schema{type: :string, format: :uuid},
      token: %Schema{type: :string, description: "The link's secret part"},
      url: %Schema{type: :string, description: "The website page the link opens"},
      expires_at: %Schema{type: :string, format: :"date-time"},
      uses: %Schema{type: :integer, description: "How many people joined through it"}
    },
    required: [:group_id, :token, :url, :expires_at, :uses]
  })
end

defmodule GamendWeb.Schemas.GroupInviteLinkResponse do
  @moduledoc "A group's invite link under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.GroupInviteLink
end

defmodule GamendWeb.Schemas.GroupInviteLinkPreview do
  @moduledoc "The group an invite link opens, as its join page shows it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GroupInviteLinkPreview",
    description: "The group an invite link opens, and whether the caller is already in it",
    type: :object,
    properties: %{
      group_id: %Schema{type: :string, format: :uuid},
      group_title: %Schema{type: :string},
      group_type: %Schema{type: :string, enum: ["public", "private", "hidden"]},
      member_count: %Schema{type: :integer},
      creator_name: %Schema{type: :string, description: "The admin who made the link"},
      expires_at: %Schema{type: :string, format: :"date-time"},
      member: %Schema{type: :boolean, description: "Whether the caller is already a member"}
    },
    required: [
      :group_id,
      :group_title,
      :group_type,
      :member_count,
      :creator_name,
      :expires_at,
      :member
    ]
  })
end

defmodule GamendWeb.Schemas.GroupInviteLinkPreviewResponse do
  @moduledoc "An invite link's group under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.GroupInviteLinkPreview
end
