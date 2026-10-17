defmodule GamendWeb.Schemas.AdminKvEntry do
  @moduledoc "A key/value entry as stored: the player's `KvEntry` plus its row id and times."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminKvEntry",
    description: "A stored key/value entry",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      key: %Schema{type: :string},
      user_id: %Schema{type: :string, description: "Empty when not user-scoped"},
      lobby_id: %Schema{type: :string, description: "Empty when not lobby-scoped"},
      data: %Schema{type: :object},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :key, :user_id, :lobby_id, :data, :metadata, :inserted_at, :updated_at]
  })
end

defmodule GamendWeb.Schemas.AdminMatchmakingTicket do
  @moduledoc "A matchmaking ticket, with the user who holds it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminMatchmakingTicket",
    description: "A matchmaking ticket",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      status: %Schema{type: :string, enum: ["queued", "matched", "cancelled"]},
      match_params: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
      min_players: %Schema{type: :integer},
      max_players: %Schema{type: :integer},
      timeout_ms: %Schema{type: :integer},
      queued_at: %Schema{type: :string, format: :"date-time"},
      matched_at: %Schema{type: :string, format: :"date-time", nullable: true},
      match_id: %Schema{type: :string, description: "Empty while queued"}
    },
    required: [
      :id,
      :user_id,
      :status,
      :match_params,
      :min_players,
      :max_players,
      :timeout_ms,
      :queued_at,
      :matched_at,
      :match_id
    ]
  })
end

defmodule GamendWeb.Schemas.AdminMatchmakingStats do
  @moduledoc "Queue depth plus the lifetime outcome counts players do not see."
  require OpenApiSpex
  alias GamendWeb.Schemas.MatchmakingQueue
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminMatchmakingStats",
    description: "Tickets by status, and waiting players per match params",
    type: :object,
    properties: %{
      queued: %Schema{type: :integer},
      matched: %Schema{type: :integer},
      cancelled: %Schema{type: :integer},
      queues: %Schema{type: :array, items: MatchmakingQueue}
    },
    required: [:queued, :matched, :cancelled, :queues]
  })
end

defmodule GamendWeb.Schemas.AdminReadyCheck do
  @moduledoc "A ready check as stored, every participant listed whatever its kind."
  require OpenApiSpex
  alias GamendWeb.Schemas.ReadyCheckParticipant
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminReadyCheck",
    description: "A ready check",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string, enum: ["ready", "accept"]},
      status: %Schema{type: :string, enum: ["pending", "passed", "failed", "cancelled"]},
      lobby_id: %Schema{type: :string, description: "Empty unless a lobby board"},
      party_id: %Schema{type: :string, description: "Empty unless a party board"},
      deadline_at: %Schema{type: :string, format: :"date-time", nullable: true},
      opened_by: %Schema{type: :string, description: "Empty when the server opened it"},
      reason: %Schema{type: :string},
      resolved_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      participants: %Schema{type: :array, items: ReadyCheckParticipant}
    },
    required: [
      :id,
      :kind,
      :status,
      :lobby_id,
      :party_id,
      :deadline_at,
      :opened_by,
      :reason,
      :resolved_at,
      :inserted_at,
      :participants
    ]
  })
end

defmodule GamendWeb.Schemas.ReadyCheckOutcomes do
  @moduledoc "Ready checks opened in the last 24 hours, by status."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReadyCheckOutcomes",
    description: "Checks per status; a status with none is left out",
    type: :object,
    additionalProperties: %Schema{type: :integer},
    example: %{"passed" => 40, "failed" => 6, "cancelled" => 1}
  })
end

defmodule GamendWeb.Schemas.StorageObject do
  @moduledoc "One stored object."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "StorageObject",
    description: "A stored object",
    type: :object,
    properties: %{
      key: %Schema{type: :string},
      size: %Schema{type: :integer, description: "Bytes"},
      last_modified: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:key, :size, :last_modified]
  })
end

defmodule GamendWeb.Schemas.StorageUsage do
  @moduledoc "How many objects, and how many bytes, sit under a prefix."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "StorageUsage",
    description: "Objects and bytes under a prefix",
    type: :object,
    properties: %{
      count: %Schema{type: :integer},
      bytes: %Schema{type: :integer}
    },
    required: [:count, :bytes]
  })
end

defmodule GamendWeb.Schemas.RetentionStatus do
  @moduledoc "The last retention sweep: when, how long, and rows removed per class."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "RetentionStatus",
    description: "The last retention sweep",
    type: :object,
    properties: %{
      last_run_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Null before the first sweep"
      },
      duration_ms: %Schema{type: :integer, nullable: true},
      results: %Schema{
        type: :object,
        description: "Rows removed per retention class",
        additionalProperties: %Schema{type: :integer}
      }
    },
    required: [:last_run_at, :duration_ms, :results]
  })
end

defmodule GamendWeb.Schemas.AnalyticsSummary do
  @moduledoc "Today's headline numbers: activity, retention and payer conversion."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  @rate %Schema{
    type: :number,
    format: :float,
    nullable: true,
    description: "0.0-1.0; null when there is nothing to divide by yet"
  }

  OpenApiSpex.schema(%{
    title: "AnalyticsSummary",
    description: "DAU / WAU / MAU, D1 / D7 / D30 and payer conversion",
    type: :object,
    properties: %{
      day: %Schema{type: :string, format: :date},
      segment: %Schema{
        type: :string,
        enum: ["all", "registered", "guest"],
        description: "Which accounts the numbers count"
      },
      dau: %Schema{type: :integer},
      wau: %Schema{type: :integer},
      mau: %Schema{type: :integer},
      stickiness: @rate,
      new_users_7d: %Schema{type: :integer},
      new_users_30d: %Schema{type: :integer},
      d1: @rate,
      d7: @rate,
      d30: @rate,
      payers_30d: %Schema{type: :integer},
      conversion_30d: @rate
    },
    required: [
      :day,
      :segment,
      :dau,
      :wau,
      :mau,
      :stickiness,
      :new_users_7d,
      :new_users_30d,
      :d1,
      :d7,
      :d30,
      :payers_30d,
      :conversion_30d
    ]
  })
end

defmodule GamendWeb.Schemas.AnalyticsDay do
  @moduledoc "One day of activity and its cohort's retention."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  @rate %Schema{type: :number, format: :float, nullable: true}

  OpenApiSpex.schema(%{
    title: "AnalyticsDay",
    description:
      "A day's active players, the 7 and 30 days ending on it, its new players " <>
        "and that cohort's D1 / D7 / D30",
    type: :object,
    properties: %{
      day: %Schema{type: :string, format: :date},
      active: %Schema{type: :integer},
      wau: %Schema{
        type: :integer,
        description: "Distinct players of the 7 days ending on the day"
      },
      mau: %Schema{
        type: :integer,
        description: "Distinct players of the 30 days ending on the day"
      },
      stickiness: %Schema{
        type: :number,
        format: :float,
        nullable: true,
        description: "active ÷ mau of the day"
      },
      new_users: %Schema{type: :integer},
      d1: @rate,
      d7: @rate,
      d30: @rate
    },
    required: [:day, :active, :wau, :mau, :stickiness, :new_users, :d1, :d7, :d30]
  })
end

defmodule GamendWeb.Schemas.AnalyticsDaily do
  @moduledoc "A run of days, oldest first."
  require OpenApiSpex
  alias GamendWeb.Schemas.AnalyticsDay
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AnalyticsDaily",
    description: "Per-day activity and cohort retention",
    type: :object,
    properties: %{
      days: %Schema{type: :integer},
      series: %Schema{type: :array, items: AnalyticsDay}
    },
    required: [:days, :series]
  })
end

defmodule GamendWeb.Schemas.EconomyTotal do
  @moduledoc "One currency and ledger reason, summed over the window."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EconomyTotal",
    description: "Granted and spent for one currency and reason",
    type: :object,
    properties: %{
      currency: %Schema{type: :string},
      reason: %Schema{type: :string},
      granted: %Schema{type: :integer},
      spent: %Schema{type: :integer},
      net: %Schema{type: :integer},
      entries: %Schema{type: :integer}
    },
    required: [:currency, :reason, :granted, :spent, :net, :entries]
  })
end

defmodule GamendWeb.Schemas.EconomyFlowDay do
  @moduledoc "One day, currency and ledger reason."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EconomyFlowDay",
    description: "Granted and spent for one day, currency and reason",
    type: :object,
    properties: %{
      day: %Schema{type: :string, format: :date},
      currency: %Schema{type: :string},
      reason: %Schema{type: :string},
      granted: %Schema{type: :integer},
      spent: %Schema{type: :integer},
      entries: %Schema{type: :integer}
    },
    required: [:day, :currency, :reason, :granted, :spent, :entries]
  })
end

defmodule GamendWeb.Schemas.AnalyticsEconomy do
  @moduledoc "Currency flow over a window: totals per reason, and per day."
  require OpenApiSpex
  alias GamendWeb.Schemas.{EconomyFlowDay, EconomyTotal}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AnalyticsEconomy",
    description: "Currency granted and spent, per reason and per day",
    type: :object,
    properties: %{
      days: %Schema{type: :integer},
      totals: %Schema{type: :array, items: EconomyTotal},
      flow: %Schema{type: :array, items: EconomyFlowDay}
    },
    required: [:days, :totals, :flow]
  })
end

defmodule GamendWeb.Schemas.CounterTotal do
  @moduledoc "One counter key, summed over the window."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CounterTotal",
    description: "A counter's total",
    type: :object,
    properties: %{key: %Schema{type: :string}, total: %Schema{type: :integer}},
    required: [:key, :total]
  })
end

defmodule GamendWeb.Schemas.AnalyticsCounts do
  @moduledoc "Daily counters matching a key or `prefix*`."
  require OpenApiSpex
  alias GamendWeb.Schemas.CounterTotal
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AnalyticsCounts",
    description: "Counter totals, and each counter by ISO day",
    type: :object,
    properties: %{
      key: %Schema{type: :string, description: "The key or `prefix*` asked for"},
      days: %Schema{type: :integer},
      totals: %Schema{type: :array, items: CounterTotal},
      series: %Schema{
        type: :object,
        description: "Counter key to ISO day to count",
        additionalProperties: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :integer}
        }
      }
    },
    required: [:key, :days, :totals, :series]
  })
end

defmodule GamendWeb.Schemas.AdminKvEntryPage do
  @moduledoc "A page of stored key/value entries."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminKvEntry
end

defmodule GamendWeb.Schemas.AdminKvEntryResponse do
  @moduledoc "One stored key/value entry under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminKvEntry
end

defmodule GamendWeb.Schemas.AdminMatchmakingTicketPage do
  @moduledoc "A page of matchmaking tickets."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminMatchmakingTicket
end

defmodule GamendWeb.Schemas.AdminMatchmakingTicketResponse do
  @moduledoc "One matchmaking ticket under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminMatchmakingTicket
end

defmodule GamendWeb.Schemas.AdminMatchmakingStatsResponse do
  @moduledoc "Matchmaking statistics under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminMatchmakingStats
end

defmodule GamendWeb.Schemas.AdminReadyCheckPage do
  @moduledoc "A page of ready checks."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminReadyCheck
end

defmodule GamendWeb.Schemas.AdminReadyCheckResponse do
  @moduledoc "One ready check under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminReadyCheck
end

defmodule GamendWeb.Schemas.ReadyCheckOutcomesResponse do
  @moduledoc "Ready check outcomes under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ReadyCheckOutcomes
end

defmodule GamendWeb.Schemas.StorageObjectPage do
  @moduledoc "A page of stored objects."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.StorageObject
end

defmodule GamendWeb.Schemas.StorageObjectResponse do
  @moduledoc "One stored object under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.StorageObject
end

defmodule GamendWeb.Schemas.StorageUsageResponse do
  @moduledoc "Storage usage under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.StorageUsage
end

defmodule GamendWeb.Schemas.RetentionStatusResponse do
  @moduledoc "The last retention sweep under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.RetentionStatus
end

defmodule GamendWeb.Schemas.AnalyticsSummaryResponse do
  @moduledoc "The analytics summary under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AnalyticsSummary
end

defmodule GamendWeb.Schemas.AnalyticsDailyResponse do
  @moduledoc "The daily series under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AnalyticsDaily
end

defmodule GamendWeb.Schemas.AnalyticsEconomyResponse do
  @moduledoc "Currency flow under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AnalyticsEconomy
end

defmodule GamendWeb.Schemas.AnalyticsCountsResponse do
  @moduledoc "Daily counters under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AnalyticsCounts
end
