defmodule GamendWeb.Schemas.AdminLeaderboardRecord do
  @moduledoc """
  A leaderboard record as stored: the admin's view, with no computed rank
  window. A label record has an empty `user_id`; a user's record an empty
  `label`.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminLeaderboardRecord",
    description: "A stored leaderboard record",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      leaderboard_id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, description: "Empty for a label record"},
      label: %Schema{type: :string, description: "Empty for a user's record"},
      score: %Schema{type: :integer},
      rank: %Schema{type: :integer, nullable: true, description: "Null until ranked"},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :leaderboard_id,
      :user_id,
      :label,
      :score,
      :rank,
      :metadata,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminTournament do
  @moduledoc "A tournament's full configuration, as an admin edits it."
  require OpenApiSpex
  alias Gamend.Tournaments.Tournament
  alias Gamend.Tournaments.TournamentState
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminTournament",
    description: "A tournament's configuration",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      slug: %Schema{type: :string},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{type: :string},
      state: %Schema{
        type: :string,
        enum: TournamentState.all()
      },
      registration_opens_at: %Schema{type: :string, format: :"date-time", nullable: true},
      starts_at: %Schema{type: :string, format: :"date-time", nullable: true},
      ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
      recur: %Schema{type: :string, description: "Cron expression; empty for a one-shot"},
      max_entries: %Schema{type: :integer, nullable: true},
      team_size: %Schema{type: :integer},
      bracket_size: %Schema{type: :integer},
      round_window_sec: %Schema{type: :integer},
      deadline_policy: %Schema{
        type: :string,
        enum: Tournament.deadline_policies(),
        description: "What an unplayed match comes to at its deadline"
      },
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :slug,
      :title,
      :description,
      :icon_url,
      :state,
      :registration_opens_at,
      :starts_at,
      :ends_at,
      :recur,
      :max_entries,
      :team_size,
      :bracket_size,
      :round_window_sec,
      :deadline_policy,
      :metadata,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminQuest do
  @moduledoc "A quest's definition, as an admin edits it: no player's progress."
  require OpenApiSpex
  alias Gamend.Quests.Quest
  alias GamendWeb.Schemas.{QuestObjective, QuestReward}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminQuest",
    description: "A quest definition",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      key: %Schema{type: :string},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{type: :string},
      sort_order: %Schema{type: :integer},
      hidden: %Schema{type: :boolean},
      reset: %Schema{type: :string, enum: Quest.resets()},
      reset_interval_days: %Schema{type: :integer, nullable: true},
      category: %Schema{type: :string},
      group_key: %Schema{type: :string},
      group_title: %Schema{type: :string},
      objectives: %Schema{type: :array, items: QuestObjective},
      rewards: %Schema{type: :array, items: QuestReward},
      auto_claim: %Schema{type: :boolean},
      code_only: %Schema{type: :boolean, description: "Only a redemption code finishes it"},
      prerequisite_quest_key: %Schema{type: :string},
      starts_at: %Schema{type: :string, format: :"date-time", nullable: true},
      ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
      active: %Schema{type: :boolean},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
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
      :group_title,
      :objectives,
      :rewards,
      :auto_claim,
      :code_only,
      :prerequisite_quest_key,
      :starts_at,
      :ends_at,
      :active,
      :metadata,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminQuestProgress do
  @moduledoc """
  A progress row as `GamendWeb.Serializers.serialize_quest_progress/1` sends
  it: the same fields as the realtime `QuestProgress`, with ISO times.
  """
  require OpenApiSpex
  alias Gamend.Quests.QuestStatus
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminQuestProgress",
    description: "A user's progress row for one quest and period",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      quest_key: %Schema{type: :string},
      period_key: %Schema{type: :string},
      objective_progress: %Schema{type: :object, additionalProperties: %Schema{type: :integer}},
      status: %Schema{
        type: :string,
        enum: QuestStatus.all()
      },
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      claimed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :user_id,
      :quest_key,
      :period_key,
      :objective_progress,
      :status,
      :completed_at,
      :claimed_at,
      :metadata,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminQuestClaim do
  @moduledoc "What a claim on a user's behalf paid, and the row it left."
  require OpenApiSpex
  alias GamendWeb.Schemas.{AdminQuestProgress, QuestReward}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminQuestClaim",
    description: "A claimed progress row and the rewards granted",
    type: :object,
    properties: %{
      progress: AdminQuestProgress,
      rewards: %Schema{type: :array, items: QuestReward}
    },
    required: [:progress, :rewards]
  })
end

defmodule GamendWeb.Schemas.QuestFunnel do
  @moduledoc "How many progress rows one quest has in each status."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "QuestFunnel",
    description: "Progress rows per status; a status with none is left out",
    type: :object,
    additionalProperties: %Schema{type: :integer},
    example: %{"active" => 40, "completed" => 12, "claimed" => 9}
  })
end

defmodule GamendWeb.Schemas.AdminWallet do
  @moduledoc "One user's balance in one currency."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminWallet",
    description: "A wallet",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      currency: %Schema{type: :string},
      balance: %Schema{type: :integer}
    },
    required: [:id, :user_id, :currency, :balance]
  })
end

defmodule GamendWeb.Schemas.AdminLedgerEntry do
  @moduledoc "A wallet change, with the user it belongs to: the admin's `LedgerEntry`."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminLedgerEntry",
    description: "A wallet change",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      currency: %Schema{type: :string},
      delta: %Schema{type: :integer},
      balance_after: %Schema{type: :integer},
      reason: %Schema{type: :string},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :user_id,
      :currency,
      :delta,
      :balance_after,
      :reason,
      :metadata,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminInventoryItem do
  @moduledoc "One user's stack of one item."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminInventoryItem",
    description: "An item stack",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      item: %Schema{type: :string},
      quantity: %Schema{type: :integer},
      metadata: %Schema{type: :object}
    },
    required: [:id, :user_id, :item, :quantity, :metadata]
  })
end

defmodule GamendWeb.Schemas.WalletBalance do
  @moduledoc "A user's balance in one currency after a change."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WalletBalance",
    description: "The balance after the change",
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      currency: %Schema{type: :string},
      balance: %Schema{type: :integer}
    },
    required: [:user_id, :currency, :balance]
  })
end

defmodule GamendWeb.Schemas.ItemQuantity do
  @moduledoc "A user's quantity of one item after a change."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ItemQuantity",
    description: "The quantity after the change",
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      item: %Schema{type: :string},
      quantity: %Schema{type: :integer}
    },
    required: [:user_id, :item, :quantity]
  })
end

defmodule GamendWeb.Schemas.AdminLeaderboardRecordResponse do
  @moduledoc "One stored record under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminLeaderboardRecord
end

defmodule GamendWeb.Schemas.AdminTournamentResponse do
  @moduledoc "One tournament configuration under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminTournament
end

defmodule GamendWeb.Schemas.AdminQuestPage do
  @moduledoc "A page of quest definitions."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminQuest
end

defmodule GamendWeb.Schemas.AdminQuestResponse do
  @moduledoc "One quest definition under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminQuest
end

defmodule GamendWeb.Schemas.AdminQuestCode do
  @moduledoc "One redemption code of a code-only quest."
  require OpenApiSpex
  alias Gamend.Quests.QuestCodeStatus
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminQuestCode",
    description: "A redemption code",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      quest_key: %Schema{type: :string},
      token: %Schema{type: :string, description: "The code as people see it"},
      max_uses: %Schema{
        type: :integer,
        nullable: true,
        description: "1 is single-use, N the first N players, null every player once"
      },
      uses: %Schema{type: :integer, description: "How many players redeemed it"},
      status: %Schema{type: :string, enum: QuestCodeStatus.all()},
      metadata: %Schema{
        type: :object,
        description: "Copied onto each player's progress row, where they can read it"
      },
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :quest_key,
      :token,
      :max_uses,
      :uses,
      :status,
      :metadata,
      :inserted_at,
      :updated_at
    ]
  })
end

defmodule GamendWeb.Schemas.AdminQuestCodeBatch do
  @moduledoc "How many redemption codes one generate made."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AdminQuestCodeBatch",
    description: "The result of generating codes; read them with the codes list",
    type: :object,
    properties: %{created: %Schema{type: :integer}},
    required: [:created]
  })
end

defmodule GamendWeb.Schemas.AdminQuestCodePage do
  @moduledoc "A page of redemption codes."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminQuestCode
end

defmodule GamendWeb.Schemas.AdminQuestCodeResponse do
  @moduledoc "One redemption code under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminQuestCode
end

defmodule GamendWeb.Schemas.AdminQuestCodeBatchResponse do
  @moduledoc "A generate's result under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminQuestCodeBatch
end

defmodule GamendWeb.Schemas.AdminQuestProgressPage do
  @moduledoc "A page of progress rows."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminQuestProgress
end

defmodule GamendWeb.Schemas.AdminQuestProgressResponse do
  @moduledoc "One progress row under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminQuestProgress
end

defmodule GamendWeb.Schemas.AdminQuestClaimResponse do
  @moduledoc "A claim on a user's behalf under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.AdminQuestClaim
end

defmodule GamendWeb.Schemas.QuestFunnelResponse do
  @moduledoc "A quest's funnel under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.QuestFunnel
end

defmodule GamendWeb.Schemas.AdminWalletPage do
  @moduledoc "A page of wallets."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminWallet
end

defmodule GamendWeb.Schemas.AdminLedgerEntryPage do
  @moduledoc "A page of ledger entries."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminLedgerEntry
end

defmodule GamendWeb.Schemas.AdminInventoryItemPage do
  @moduledoc "A page of item stacks."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.AdminInventoryItem
end

defmodule GamendWeb.Schemas.WalletBalanceResponse do
  @moduledoc "A balance under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.WalletBalance
end

defmodule GamendWeb.Schemas.ItemQuantityResponse do
  @moduledoc "An item quantity under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ItemQuantity
end
