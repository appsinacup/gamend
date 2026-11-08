defmodule GamendWeb.Schemas.AdminUser do
  @moduledoc "A user as the admin API sends it: the account flags a player never sees."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminUser",
    description: "A user, with account flags",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      email: %Schema{type: :string, description: "Empty for a device or OAuth-only account"},
      username: %Schema{type: :string},
      display_name: %Schema{type: :string},
      is_admin: %Schema{type: :boolean},
      is_activated: %Schema{type: :boolean},
      metadata: %Schema{type: :object},
      lobby_id: %Schema{type: :string, description: "Empty when not in a lobby"},
      party_id: %Schema{type: :string, description: "Empty when not in a party"},
      is_online: %Schema{type: :boolean},
      last_seen_at: %Schema{type: :string, format: :"date-time"},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :email,
      :username,
      :display_name,
      :is_admin,
      :is_activated,
      :metadata,
      :lobby_id,
      :party_id,
      :is_online,
      :last_seen_at,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminSession do
  @moduledoc "A browser session token, with the user it signs in."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminSession",
    description: "A browser session",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      username: %Schema{type: :string},
      display_name: %Schema{type: :string},
      user_email: %Schema{type: :string},
      context: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      authenticated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [
      :id,
      :user_id,
      :username,
      :display_name,
      :user_email,
      :context,
      :inserted_at,
      :authenticated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminPushToken do
  @moduledoc "A device push token, with the name of the user it belongs to."
  require OpenApiSpex
  alias Gamend.Push.Platform
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminPushToken",
    description: "A registered device push token",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      user_name: %Schema{type: :string},
      token: %Schema{type: :string},
      platform: %Schema{type: :string, enum: Platform.all()},
      provider: %Schema{type: :string, description: "fcm or apns; empty picks by platform"},
      device_id: %Schema{type: :string, description: "Empty when unset"},
      disabled_at: %Schema{type: :string, format: :"date-time", nullable: true},
      last_used_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :user_id,
      :user_name,
      :token,
      :platform,
      :provider,
      :device_id,
      :disabled_at,
      :last_used_at,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.ChatReport do
  @moduledoc "A report against a chat message, as the moderation queue holds it."
  require OpenApiSpex
  alias Gamend.Chat.ChatReportStatus
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ChatReport",
    description: "A chat report",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      reporter_id: %Schema{type: :string, description: "Empty when the word filter filed it"},
      reporter_name: %Schema{type: :string},
      reported_user_id: %Schema{type: :string, format: :uuid},
      reported_user_name: %Schema{type: :string},
      message_id: %Schema{type: :string},
      content_snapshot: %Schema{type: :string},
      reason: %Schema{type: :string},
      status: %Schema{
        type: :string,
        enum: ChatReportStatus.all()
      },
      resolved_by: %Schema{type: :string, description: "Empty until resolved"},
      resolved_by_name: %Schema{type: :string},
      resolution_note: %Schema{type: :string},
      resolved_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :reporter_id,
      :reporter_name,
      :reported_user_id,
      :reported_user_name,
      :message_id,
      :content_snapshot,
      :reason,
      :status,
      :resolved_by,
      :resolved_by_name,
      :resolution_note,
      :resolved_at,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.ChatFilterWord do
  @moduledoc "A word on the chat blocklist."
  require OpenApiSpex
  alias Gamend.Chat.FilterSeverity
  alias Gamend.Chat.MatchMode
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ChatFilterWord",
    description: "A blocklist word",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      word: %Schema{type: :string},
      severity: %Schema{
        type: :string,
        enum: FilterSeverity.all()
      },
      match_mode: %Schema{type: :string, enum: MatchMode.all()},
      lang: %Schema{type: :string, description: "Bundled-list provenance, empty when hand-added"},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :word, :severity, :match_mode, :lang, :inserted_at, :updated_at]
  })
end

defmodule GamendWeb.Schemas.ChatFilterLanguages do
  @moduledoc "The languages with a bundled word list to import."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ChatFilterLanguages",
    description: "Importable bundled lists",
    type: :object,
    properties: %{
      languages: %Schema{type: :array, items: %Schema{type: :string}, description: "e.g. `en`"}
    },
    required: [:languages]
  })
end

defmodule GamendWeb.Schemas.ChatFilterHit do
  @moduledoc "One blocklist word a phrase matched."
  require OpenApiSpex
  alias Gamend.Chat.FilterSeverity
  alias Gamend.Chat.MatchMode
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ChatFilterHit",
    description: "A matched blocklist word",
    type: :object,
    properties: %{
      word: %Schema{type: :string},
      severity: %Schema{
        type: :string,
        enum: FilterSeverity.all()
      },
      match_mode: %Schema{type: :string, enum: MatchMode.all()}
    },
    required: [:word, :severity, :match_mode]
  })
end

defmodule GamendWeb.Schemas.ChatFilterTest do
  @moduledoc "What the chat pipeline would do with a phrase."
  require OpenApiSpex
  alias GamendWeb.Schemas.ChatFilterHit
  alias OpenApiSpex.Schema

  require Gamend.Chat.FilterSeverity, as: FilterSeverity

  OpenApiSpex.schema(%{
    title: "ChatFilterTest",
    description: "A phrase's filter outcome",
    type: :object,
    properties: %{
      phrase: %Schema{type: :string},
      action: %Schema{
        type: :string,
        enum: [
          FilterSeverity.block(),
          FilterSeverity.mask(),
          FilterSeverity.flag(),
          FilterSeverity.allow()
        ]
      },
      content: %Schema{type: :string, description: "What would be stored; empty when blocked"},
      flagged_words: %Schema{type: :array, items: %Schema{type: :string}},
      hits: %Schema{type: :array, items: ChatFilterHit}
    },
    required: [:phrase, :action, :content, :flagged_words, :hits]
  })
end

defmodule GamendWeb.Schemas.ImportedCount do
  @moduledoc "How many rows an import added."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ImportedCount",
    description: "Rows imported; duplicates are skipped and not counted",
    type: :object,
    properties: %{imported: %Schema{type: :integer}},
    required: [:imported]
  })
end

defmodule GamendWeb.Schemas.AdminUserResponse do
  @moduledoc "One user under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminUser
end

defmodule GamendWeb.Schemas.AdminSessionPage do
  @moduledoc "A page of browser sessions."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminSession
end

defmodule GamendWeb.Schemas.AdminPushTokenPage do
  @moduledoc "A page of device push tokens."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminPushToken
end

defmodule GamendWeb.Schemas.ChatReportPage do
  @moduledoc "A page of chat reports."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.ChatReport
end

defmodule GamendWeb.Schemas.ChatReportResponse do
  @moduledoc "One chat report under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatReport
end

defmodule GamendWeb.Schemas.ChatFilterWordPage do
  @moduledoc "A page of blocklist words."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.ChatFilterWord
end

defmodule GamendWeb.Schemas.ChatFilterWordResponse do
  @moduledoc "One blocklist word under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatFilterWord
end

defmodule GamendWeb.Schemas.ChatFilterLanguagesResponse do
  @moduledoc "Importable languages under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatFilterLanguages
end

defmodule GamendWeb.Schemas.ChatFilterTestResponse do
  @moduledoc "A phrase's filter outcome under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ChatFilterTest
end

defmodule GamendWeb.Schemas.ImportedCountResponse do
  @moduledoc "The imported count under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ImportedCount
end

defmodule GamendWeb.Schemas.AdminBan do
  @moduledoc "A ban (`Gamend.Bans`) as the admin API sends it: an IP, an account or a chat mute, with names."
  require OpenApiSpex
  alias Gamend.Bans.BanKind
  alias OpenApiSpex.Schema

  @plugin "plugin"
  @admin "admin"

  @api_source "api"

  OpenApiSpex.schema(%{
    title: "AdminBan",
    description: "An IP, account or chat ban, active or ended",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string, enum: BanKind.all()},
      subject: %Schema{
        type: :string,
        description: "The IP (an IPv6 one as its /64), or the user id"
      },
      user_id: %Schema{type: :string, description: "The banned user; empty for an IP ban"},
      user_name: %Schema{type: :string},
      scope: %Schema{
        type: :string,
        description: "A chat ban's reach (`global`, `lobby`, `group`, `party`); empty otherwise"
      },
      scope_ref_id: %Schema{
        type: :string,
        description: "A scoped chat ban's room; empty otherwise"
      },
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      reason: %Schema{type: :string},
      source: %Schema{type: :string, enum: [@admin, @api_source, "room", @plugin, "system"]},
      banned_by: %Schema{type: :string, description: "Empty when no one placed it by hand"},
      banned_by_name: %Schema{type: :string},
      lifted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      lifted_by: %Schema{type: :string, description: "Empty unless an admin lifted it"},
      lifted_by_name: %Schema{type: :string},
      active: %Schema{type: :boolean, description: "In force now"},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :kind,
      :subject,
      :user_id,
      :user_name,
      :scope,
      :scope_ref_id,
      :expires_at,
      :reason,
      :source,
      :banned_by,
      :banned_by_name,
      :lifted_at,
      :lifted_by,
      :lifted_by_name,
      :active,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminBanPage do
  @moduledoc "A page of bans."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminBan
end

defmodule GamendWeb.Schemas.AdminBanResponse do
  @moduledoc "One ban under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminBan
end
