defmodule GamendWeb.Schemas.ChatMessage do
  @moduledoc """
  A chat message as `GamendWeb.Serializers.serialize_chat_message/2` sends it.
  The chat endpoints ask for `updated_at`; `sender_email` is admin-only.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  require Gamend.Chat.ChatType, as: ChatType

  OpenApiSpex.schema(%{
    title: "ChatMessage",
    description: "A chat message",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      content: %Schema{type: :string},
      metadata: %Schema{type: :object},
      sender_id: %Schema{type: :string, format: :uuid},
      sender_name: %Schema{type: :string, description: "Sender's display name"},
      chat_type: %Schema{
        type: :string,
        enum: [ChatType.lobby(), ChatType.group(), ChatType.party(), ChatType.friend()]
      },
      chat_ref_id: %Schema{
        type: :string,
        format: :uuid,
        description: "The lobby, group or party id, or the friend's user id"
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"},
      sender_email: %Schema{type: :string, description: "Admin endpoints only"}
    },
    required: [
      :id,
      :content,
      :metadata,
      :sender_id,
      :sender_name,
      :chat_type,
      :chat_ref_id,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.ChatMessagePage do
  @moduledoc "A page of chat messages."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.ChatMessage
end

defmodule GamendWeb.Schemas.ChatReadCursor do
  @moduledoc "How far a user has read a conversation, as `mark_chat_read` leaves it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ChatReadCursor",
    description: "The last message read in a conversation",
    type: :object,
    properties: %{
      chat_type: %Schema{type: :string},
      chat_ref_id: %Schema{type: :string, format: :uuid},
      last_read_message_id: %Schema{type: :string, format: :uuid},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:chat_type, :chat_ref_id, :last_read_message_id, :updated_at]
  })
end

defmodule GamendWeb.Schemas.ChatUnread do
  @moduledoc "Unread messages in one conversation."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ChatUnread",
    description: "Unread message count",
    type: :object,
    properties: %{unread_count: %Schema{type: :integer}},
    required: [:unread_count]
  })
end

defmodule GamendWeb.Schemas.ChatUnreadResponse do
  @moduledoc "The unread count under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatUnread
end

defmodule GamendWeb.Schemas.ChatMuteRecord do
  @moduledoc """
  A mute as the moderation endpoints list it. The realtime `ChatMute` event is
  the muted player's notice of one, a smaller shape, hence the distinct name.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  require Gamend.Bans.BanScope, as: BanScope
  require Gamend.Chat.ChatType, as: ChatType

  OpenApiSpex.schema(%{
    title: "ChatMuteRecord",
    description: "A chat mute",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid, description: "The muted player"},
      scope: %Schema{
        type: :string,
        enum: [BanScope.global(), ChatType.lobby(), ChatType.group(), ChatType.party()]
      },
      scope_ref_id: %Schema{
        type: :string,
        description: "The lobby, group or party; empty when global"
      },
      expires_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Null for a mute with no end"
      },
      reason: %Schema{type: :string},
      muted_by: %Schema{type: :string, description: "Who muted; empty for the system"},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :user_id,
      :scope,
      :scope_ref_id,
      :expires_at,
      :reason,
      :muted_by,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.ChatMuteRecordPage do
  @moduledoc "A page of mutes."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.ChatMuteRecord
end

defmodule GamendWeb.Schemas.ChatMuteRecordResponse do
  @moduledoc "The new mute under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatMuteRecord
end

defmodule GamendWeb.Schemas.ChatMessageResponse do
  @moduledoc "One chat message under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatMessage
end

defmodule GamendWeb.Schemas.ChatReadCursorResponse do
  @moduledoc "The read cursor under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatReadCursor
end
