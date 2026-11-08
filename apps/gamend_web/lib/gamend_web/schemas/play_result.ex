defmodule GamendWeb.Schemas.PlayResultStat do
  @moduledoc "One event key's count and sum of values in a result."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayResultStat",
    description: "How many events a key has in a result, and the sum of their values",
    type: :object,
    properties: %{
      count: %Schema{type: :integer},
      sum: %Schema{type: :number}
    },
    required: [:count, :sum]
  })
end

defmodule GamendWeb.Schemas.PlayResult do
  @moduledoc """
  One play by one player (`Gamend.Results`), with `stats`: each event key's
  count and sum. An unset lobby is `""`.
  """
  require OpenApiSpex
  alias Gamend.Results.ResultStatus
  alias OpenApiSpex.Schema

  require Gamend.Results.ResultVisibility, as: ResultVisibility

  OpenApiSpex.schema(%{
    title: "PlayResult",
    description: "One play by one player, and its stats by event key",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      lobby_id: %Schema{type: :string, description: "The lobby it ran in; empty when none"},
      kind: %Schema{type: :string, description: "What was played"},
      visibility: %Schema{
        type: :string,
        enum: [
          ResultVisibility.public(),
          ResultVisibility.owner_only(),
          ResultVisibility.lobby_members_only(),
          ResultVisibility.owner_or_lobby_member(),
          "admin_only",
          ResultVisibility.server_only()
        ]
      },
      status: %Schema{type: :string, enum: ResultStatus.all()},
      metadata: %Schema{type: :object, description: "What the play was: its settings"},
      started_at: %Schema{type: :string, format: :"date-time"},
      ended_at: %Schema{type: :string, format: :"date-time", nullable: true},
      stats: %Schema{
        type: :object,
        additionalProperties: GamendWeb.Schemas.PlayResultStat,
        description: "By event key"
      }
    },
    required: [
      :id,
      :user_id,
      :lobby_id,
      :kind,
      :visibility,
      :status,
      :metadata,
      :started_at,
      :stats
    ]
  })
end

defmodule GamendWeb.Schemas.PlayResultEvent do
  @moduledoc "One thing that happened in a play, at its time into it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayResultEvent",
    description: "One thing that happened in a play; ids are time-ordered",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      result_id: %Schema{type: :string, format: :uuid},
      elapsed_ms: %Schema{type: :integer, description: "Milliseconds since the play began"},
      key: %Schema{type: :string, description: "What happened"},
      value: %Schema{type: :number, nullable: true},
      metadata: %Schema{type: :object}
    },
    required: [:id, :result_id, :elapsed_ms, :key, :metadata]
  })
end

defmodule GamendWeb.Schemas.PlayResultEvents do
  @moduledoc "A result's events, oldest first."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayResultEvents",
    description: "A result's events, oldest first",
    type: :object,
    properties: %{
      result_id: %Schema{type: :string, format: :uuid},
      events: %Schema{type: :array, items: GamendWeb.Schemas.PlayResultEvent}
    },
    required: [:result_id, :events]
  })
end

defmodule GamendWeb.Schemas.PlayResultPage do
  @moduledoc "A page of the caller's results."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.PlayResult
end

defmodule GamendWeb.Schemas.PlayResultResponse do
  @moduledoc "One result under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PlayResult
end

defmodule GamendWeb.Schemas.PlayResultEventsResponse do
  @moduledoc "A result's events under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PlayResultEvents
end
