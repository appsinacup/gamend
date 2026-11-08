defmodule GamendWeb.Schemas.OAuthSessionStatus do
  @moduledoc """
  A provider sign-in started with `GET /api/v1/auth/{provider}`, as the client
  polls it. The tokens ride in `session`, once.
  """

  require OpenApiSpex
  alias Gamend.OAuth.SessionStatus
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OAuthSessionStatus",
    description: "Where a provider sign-in stands",
    type: :object,
    properties: %{
      status: %Schema{
        type: :string,
        description: "`pending` until the player finishes at the provider",
        enum: SessionStatus.all()
      },
      error: %Schema{
        type: :string,
        description:
          "The code when `status` is `error` (`account_not_activated`, `sign_in_failed`, " <>
            "`authentication_failed`), else empty"
      },
      message: %Schema{type: :string, description: "For a person; may be empty"},
      session: %Schema{
        allOf: [GamendWeb.Schemas.Session],
        nullable: true,
        description:
          "The signed-in session, on the first read after `completed`; null on every other"
      }
    },
    required: [:status, :error, :message, :session]
  })
end
