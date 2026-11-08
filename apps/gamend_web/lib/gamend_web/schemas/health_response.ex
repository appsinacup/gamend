defmodule GamendWeb.Schemas.Health do
  @moduledoc "The health check's answer."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  @ok "ok"

  OpenApiSpex.schema(%{
    title: "Health",
    description: "The API is up",
    type: :object,
    properties: %{
      status: %Schema{type: :string, description: "Always `ok` when answered", example: @ok},
      timestamp: %Schema{
        type: :string,
        format: :"date-time",
        description: "The server's clock",
        example: "2025-11-22T16:00:00Z"
      }
    },
    required: [:status, :timestamp]
  })
end

defmodule GamendWeb.Schemas.HealthResponse do
  @moduledoc "The health check under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Health
end
