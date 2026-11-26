defmodule GamendWeb.Schemas.SentMessage do
  @moduledoc "An email or push that went out (`Gamend.Sent`), as the admin API sends it."
  require OpenApiSpex
  alias Gamend.Sent.SentKind
  alias Gamend.Sent.SentStatus
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  require Gamend.Notifications.NotificationChannel, as: NotificationChannel

  @properties %{
    id: %Schema{type: :string, format: :uuid},
    channel: %Schema{
      type: :string,
      enum: [NotificationChannel.email(), NotificationChannel.push()]
    },
    kind: %Schema{type: :string, enum: SentKind.all(), description: "What it was"},
    group: %Schema{type: :string, description: "The notification group. Empty for none"},
    batch_id: %Schema{
      type: :string,
      description: "The announcement it was part of. Empty for a single send"
    },
    user_id: %Schema{type: :string, description: "Empty for a bare address (a test email)"},
    user_name: %Schema{type: :string},
    address: %Schema{type: :string, description: "The email address, or the device"},
    subject: %Schema{type: :string, description: "The email's subject or the push's title"},
    body: FreeForm.object("what it said, sign-in links, codes and unsubscribe links hidden"),
    status: %Schema{type: :string, enum: SentStatus.all()},
    reason: %Schema{type: :string, description: "Why it failed. Empty when sent"},
    inserted_at: %Schema{type: :string, format: :"date-time"}
  }

  @doc false
  def properties, do: @properties

  OpenApiSpex.schema(%{
    title: "SentMessage",
    description: "An email or push that went out",
    type: :object,
    properties: @properties,
    required: Map.keys(@properties)
  })
end

defmodule GamendWeb.Schemas.SentMessagePreview do
  @moduledoc "A sent message with what its reader saw: the email's text and HTML copies."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  @properties Map.merge(GamendWeb.Schemas.SentMessage.properties(), %{
                text: %Schema{type: :string, description: "The plain-text copy. Empty for a push"},
                html: %Schema{
                  type: :string,
                  description: "The HTML copy, in today's email layout. Empty for a push"
                }
              })

  OpenApiSpex.schema(%{
    title: "SentMessagePreview",
    description: "A sent message with its text and HTML copies",
    type: :object,
    properties: @properties,
    required: Map.keys(@properties)
  })
end

defmodule GamendWeb.Schemas.SentMessagePage do
  @moduledoc "A page of sent messages."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.SentMessage
end

defmodule GamendWeb.Schemas.SentMessagePreviewResponse do
  @moduledoc "One sent message and its copies under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.SentMessagePreview
end
