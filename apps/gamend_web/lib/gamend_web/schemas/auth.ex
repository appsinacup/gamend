defmodule GamendWeb.Schemas.Session do
  @moduledoc """
  A signed-in session: what every sign-in (email, device, registration, a
  provider) and a refresh answer under `data`.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Session",
    description: "Tokens for a signed-in user",
    type: :object,
    properties: %{
      access_token: %Schema{
        type: :string,
        description:
          "JWT access token (15 min by default: `GAMEND_AUTH_ACCESS_TOKEN_TTL_MINUTES`)"
      },
      refresh_token: %Schema{
        type: :string,
        description:
          "JWT refresh token (30 days by default: `GAMEND_AUTH_REFRESH_TOKEN_TTL_DAYS`)"
      },
      expires_in: %Schema{type: :integer, description: "Seconds until the access token expires"},
      user_id: %Schema{type: :string, format: :uuid},
      username: %Schema{type: :string, description: "Unique handle"},
      display_name: %Schema{type: :string, description: "Chosen name"}
    },
    required: [:access_token, :refresh_token, :expires_in, :user_id, :username, :display_name],
    example: %{
      access_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      refresh_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      expires_in: 900,
      user_id: "0198c0de-0002-7000-8000-000000000002",
      username: "coolplayer-1234",
      display_name: "CoolPlayer"
    }
  })
end

defmodule GamendWeb.Schemas.SessionResponse do
  @moduledoc "A session under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Session
end

defmodule GamendWeb.Schemas.OAuthAuthorization do
  @moduledoc "Where to send the player to sign in, and the session to poll for the result."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OAuthAuthorization",
    description: "A started OAuth sign-in",
    type: :object,
    properties: %{
      authorization_url: %Schema{type: :string, description: "Open this for the player"},
      session_id: %Schema{
        type: :string,
        description: "Poll `GET /auth/session/{session_id}` with it"
      }
    },
    required: [:authorization_url, :session_id],
    example: %{
      authorization_url: "https://discord.com/oauth2/authorize?...",
      session_id: "abc123..."
    }
  })
end

defmodule GamendWeb.Schemas.AuthProvidersResponse do
  @moduledoc "The OAuth providers a player may sign in with, under `data`."
  alias OpenApiSpex.Schema

  use GamendWeb.Schemas.Envelope,
    data: %Schema{
      type: :array,
      items: %Schema{
        type: :string,
        enum: ["discord", "google", "apple", "facebook", "github", "steam"]
      }
    },
    description: "Enabled sign-in providers under `data`"
end

defmodule GamendWeb.Schemas.OAuthAuthorizationResponse do
  @moduledoc "A started OAuth sign-in under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.OAuthAuthorization
end

defmodule GamendWeb.Schemas.OAuthSessionStatusResponse do
  @moduledoc "An OAuth session's state under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.OAuthSessionStatus
end

defmodule GamendWeb.Schemas.ProviderLinkStatus do
  @moduledoc """
  A provider link started with `POST /api/v1/me/providers/{provider}/authorize`,
  as its owner polls it.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ProviderLinkStatus",
    description: "Where a provider link stands",
    type: :object,
    properties: %{
      status: %Schema{type: :string, enum: ["pending", "completed", "error"]},
      error: %Schema{
        type: :string,
        description:
          "The code when `status` is `error` (`provider_already_linked`, `link_failed`, " <>
            "`authentication_failed`), else empty"
      },
      message: %Schema{type: :string, description: "For a person; may be empty"},
      provider: %Schema{type: :string, description: "The provider being linked"}
    },
    required: [:status, :error, :message, :provider]
  })
end

defmodule GamendWeb.Schemas.ProviderLinkStatusResponse do
  @moduledoc "A provider link's state under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ProviderLinkStatus
end
