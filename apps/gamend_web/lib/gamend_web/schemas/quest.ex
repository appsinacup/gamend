defmodule GamendWeb.Schemas.QuestObjective do
  @moduledoc "One objective of a quest: count `target` occurrences of `event`."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "QuestObjective",
    description: "A quest objective",
    type: :object,
    properties: %{
      event: %Schema{type: :string, description: "Event name the objective counts"},
      target: %Schema{type: :integer, description: "Occurrences required"},
      params: %Schema{type: :object, description: "Event meta constraints (all must match)"}
    },
    required: [:event, :target, :params]
  })
end

defmodule GamendWeb.Schemas.QuestReward do
  @moduledoc "What a quest pays on claim."
  require OpenApiSpex
  alias Gamend.Quests.RewardType
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "QuestReward",
    description: "A quest reward",
    type: :object,
    properties: %{
      type: %Schema{type: :string, enum: RewardType.all()},
      code: %Schema{type: :string, description: "Currency or item code"},
      amount: %Schema{type: :integer, description: "Amount granted"}
    },
    required: [:type, :code, :amount]
  })
end

defmodule GamendWeb.Schemas.QuestProgress do
  @moduledoc """
  The caller's progress on a quest for the current reset period. The realtime
  `QuestProgress` event carries the same fields, plus the row's ids, with
  times in milliseconds.
  """
  require OpenApiSpex
  alias Gamend.Quests.QuestStatus
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "QuestProgress",
    description: "Progress for the current reset period",
    type: :object,
    properties: %{
      period_key: %Schema{
        type: :string,
        description: "Reset bucket (\"static\", a date or an ISO week)"
      },
      objective_progress: %Schema{
        type: :object,
        description: "Objective index (as a string) to its current count",
        additionalProperties: %Schema{type: :integer}
      },
      status: %Schema{
        type: :string,
        enum: QuestStatus.all()
      },
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      claimed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      claim_count: %Schema{
        type: :integer,
        description: "Finished runs of a repeat quest; 0 until the first claim"
      }
    },
    required: [
      :period_key,
      :objective_progress,
      :status,
      :completed_at,
      :claimed_at,
      :claim_count
    ]
  })
end

defmodule GamendWeb.Schemas.Quest do
  @moduledoc """
  A quest with the caller's progress, as `GamendWeb.Api.V1.QuestController`
  sends it. A hidden quest the caller has not completed has its title and
  description replaced by `???` and no objectives, rewards or metadata.
  """
  require OpenApiSpex
  alias Gamend.Quests.Quest
  alias GamendWeb.Schemas.{QuestObjective, QuestProgress, QuestReward}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Quest",
    description: "A quest, with the caller's progress",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      key: %Schema{type: :string, description: "Unique slug"},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{type: :string, description: "Empty when unset"},
      sort_order: %Schema{type: :integer},
      hidden: %Schema{type: :boolean, description: "Hidden until completed"},
      reset: %Schema{
        type: :string,
        enum: Quest.resets(),
        description: "When progress starts over"
      },
      reset_interval_days: %Schema{
        type: :integer,
        nullable: true,
        description: "Cadence in days when `reset` is `interval` (biweekly = 14)"
      },
      category: %Schema{
        type: :string,
        description: "Free-form grouping label for your UI; empty when unset"
      },
      group_key: %Schema{
        type: :string,
        description: "Quests sharing this list as one entry; pass `?group=` to open it"
      },
      group_size: %Schema{
        type: :integer,
        description: "How many quests the entry stands for (1 when ungrouped)"
      },
      group_title: %Schema{type: :string, description: "The collapsed group entry's title"},
      objectives: %Schema{type: :array, items: QuestObjective},
      rewards: %Schema{type: :array, items: QuestReward},
      auto_claim: %Schema{type: :boolean, description: "Rewards grant on completion"},
      code_only: %Schema{
        type: :boolean,
        description: "Only a redemption code finishes it (POST /me/quests/redeem)"
      },
      prerequisite_quest_key: %Schema{
        type: :string,
        description: "Quest that must be completed first; empty when none"
      },
      starts_at: %Schema{type: :string, format: :"date-time", nullable: true},
      ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: %Schema{type: :object},
      progress: %Schema{
        allOf: [QuestProgress],
        nullable: true,
        description: "Null when the caller has not started it, or is not signed in"
      },
      claimable: %Schema{type: :boolean, description: "Completed and waiting to be claimed"}
    },
    required: [
      :id,
      :key,
      :title,
      :description,
      :icon_url,
      :sort_order,
      :hidden,
      :reset,
      :reset_interval_days,
      :category,
      :group_key,
      :group_size,
      :group_title,
      :objectives,
      :rewards,
      :auto_claim,
      :code_only,
      :prerequisite_quest_key,
      :starts_at,
      :ends_at,
      :metadata,
      :progress,
      :claimable
    ]
  })
end

defmodule GamendWeb.Schemas.QuestClaim do
  @moduledoc "What claiming a quest paid, and the progress it left."
  require OpenApiSpex
  alias GamendWeb.Schemas.{QuestProgress, QuestReward}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "QuestClaim",
    description: "A claimed quest's progress and the rewards granted",
    type: :object,
    properties: %{
      progress: QuestProgress,
      rewards: %Schema{type: :array, items: QuestReward}
    },
    required: [:progress, :rewards]
  })
end

defmodule GamendWeb.Schemas.QuestStats do
  @moduledoc "The counters `Gamend.Quests.stats/0` returns."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "QuestStats",
    description: "Quest progress counts, cached for up to a minute",
    type: :object,
    properties: %{
      quests_total: %Schema{type: :integer},
      completed: %Schema{type: :integer},
      claimed: %Schema{type: :integer}
    },
    required: [:quests_total, :completed, :claimed]
  })
end

defmodule GamendWeb.Schemas.QuestPage do
  @moduledoc "A page of quests."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Quest
end

defmodule GamendWeb.Schemas.QuestClaimResponse do
  @moduledoc "A quest claim under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.QuestClaim
end

defmodule GamendWeb.Schemas.QuestStatsResponse do
  @moduledoc "Quest counts under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.QuestStats
end
