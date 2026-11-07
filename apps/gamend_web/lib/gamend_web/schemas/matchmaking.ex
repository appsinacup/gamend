defmodule GamendWeb.Schemas.MatchmakingTicket do
  @moduledoc "A place in the matchmaking queue."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MatchmakingTicket",
    description: "A matchmaking ticket",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      status: %Schema{type: :string, enum: ["queued", "matched", "cancelled"]},
      match_params: %Schema{
        type: :object,
        description: "String key/value pairs; only identical params match together",
        additionalProperties: %Schema{type: :string}
      },
      min_players: %Schema{type: :integer},
      max_players: %Schema{type: :integer},
      timeout_ms: %Schema{type: :integer},
      queued_at: %Schema{type: :string, format: :"date-time"},
      matched_at: %Schema{type: :string, format: :"date-time", nullable: true},
      match_id: %Schema{
        type: :string,
        description: "The lobby the ticket was matched into; empty while queued"
      },
      accept_timeout_ms: %Schema{
        type: :integer,
        description: "The ms a formed match gives its players to accept; 0 seats them at once"
      },
      lobby_id: %Schema{
        type: :string,
        description:
          "The lobby the ticket fills (its host queued from it, backfill); empty for none"
      }
    },
    required: [
      :id,
      :status,
      :match_params,
      :min_players,
      :max_players,
      :timeout_ms,
      :queued_at,
      :matched_at,
      :match_id,
      :accept_timeout_ms,
      :lobby_id
    ]
  })
end

defmodule GamendWeb.Schemas.MatchmakingQueue do
  @moduledoc "How many players wait for one set of match params."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MatchmakingQueue",
    description: "Waiting players for one set of match params",
    type: :object,
    properties: %{
      params: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
      waiting: %Schema{type: :integer}
    },
    required: [:params, :waiting]
  })
end

defmodule GamendWeb.Schemas.MatchmakingStats do
  @moduledoc "Queue depth, public: no lifetime matched/cancelled counters."
  require OpenApiSpex
  alias GamendWeb.Schemas.MatchmakingQueue
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MatchmakingStats",
    description: "Players queued, overall and per match params, deepest first",
    type: :object,
    properties: %{
      queued: %Schema{type: :integer},
      queues: %Schema{type: :array, items: MatchmakingQueue}
    },
    required: [:queued, :queues]
  })
end

defmodule GamendWeb.Schemas.CancelledCount do
  @moduledoc "How many rows a cancel call ended."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CancelledCount",
    description: "Rows cancelled; 0 when there was nothing to cancel",
    type: :object,
    properties: %{cancelled: %Schema{type: :integer}},
    required: [:cancelled]
  })
end

defmodule GamendWeb.Schemas.MatchmakingTicketResponse do
  @moduledoc "One ticket under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.MatchmakingTicket
end

defmodule GamendWeb.Schemas.MatchmakingStatsResponse do
  @moduledoc "Queue depth under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.MatchmakingStats
end

defmodule GamendWeb.Schemas.CancelledCountResponse do
  @moduledoc "The cancelled count under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.CancelledCount
end
