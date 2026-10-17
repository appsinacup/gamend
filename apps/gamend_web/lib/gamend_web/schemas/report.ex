defmodule GamendWeb.Schemas.ReportKind do
  @moduledoc "A report kind a client may file (`Gamend.Reports.Kind`)."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReportKind",
    description: "What a report can be about, and what it may carry",
    type: :object,
    properties: %{
      key: %Schema{type: :string, description: "The kind's key, sent as `kind`", example: "page"},
      topics: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Topics a report must pick one of; empty when the kind has none"
      },
      max_attachments: %Schema{type: :integer, description: "Images a report may carry"},
      max_attachment_bytes: %Schema{type: :integer, description: "Largest image, in bytes"}
    },
    required: [:key, :topics, :max_attachments, :max_attachment_bytes]
  })
end

defmodule GamendWeb.Schemas.ReportKinds do
  @moduledoc "Every report kind a client may file. A catalogue, not a page: it is short."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReportKinds",
    description: "The report kinds",
    type: :object,
    properties: %{
      kinds: %Schema{type: :array, items: GamendWeb.Schemas.ReportKind}
    },
    required: [:kinds]
  })
end

defmodule GamendWeb.Schemas.ReportKindsResponse do
  @moduledoc "The report kinds under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ReportKinds
end

defmodule GamendWeb.Schemas.ReportRequest do
  @moduledoc """
  A report from a game client. `subject` and `data` are the kind's own
  (`Gamend.Reports.Kind.cast/2` reads them); `attachments` are base64 images.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReportRequest",
    description: "A report about the game's content",
    type: :object,
    properties: %{
      kind: %Schema{type: :string, description: "A key from GET /reports/kinds", example: "page"},
      topic: %Schema{type: :string, description: "One of the kind's topics, if it has any"},
      subject: %Schema{
        type: :object,
        additionalProperties: true,
        description: "What is reported, in the kind's own shape",
        example: %{"path" => "/games"}
      },
      data: %Schema{
        type: :object,
        additionalProperties: true,
        description: "The kind's extra fields (a suggested correction)"
      },
      description: %Schema{type: :string, maxLength: 2000, description: "What happened"},
      email: %Schema{type: :string, description: "Where to send a reply, if anywhere"},
      locale: %Schema{type: :string, example: "en"},
      client: %Schema{
        type: :object,
        description: "Short device facts: user_agent, viewport, screen, platform, app_version",
        additionalProperties: %Schema{type: :string}
      },
      attachments: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :byte},
        description: "Base64 PNG, JPEG or WebP images, up to the kind's max_attachments"
      }
    },
    required: [:kind]
  })
end

defmodule GamendWeb.Schemas.ReportReceipt do
  @moduledoc "What a filed report answers: its id and status."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReportReceipt",
    description: "A filed report",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Report id"},
      kind: %Schema{type: :string},
      status: %Schema{type: :string, example: "open"}
    },
    required: [:id, :kind, :status]
  })
end

defmodule GamendWeb.Schemas.ReportReceiptResponse do
  @moduledoc "A filed report under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ReportReceipt
end
