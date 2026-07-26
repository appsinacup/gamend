defmodule GameServerWeb.Api.V1.QuestController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Quests
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Quests"])

  @objective_schema %Schema{
    type: :object,
    properties: %{
      event: %Schema{type: :string, description: "Event name the objective counts"},
      target: %Schema{type: :integer, description: "Occurrences required"},
      params: %Schema{type: :object, description: "Event meta constraints (all must match)"}
    }
  }

  @reward_schema %Schema{
    type: :object,
    properties: %{
      type: %Schema{type: :string, enum: ["currency", "item"], description: "Reward type"},
      code: %Schema{type: :string, description: "Currency or item code"},
      amount: %Schema{type: :integer, description: "Amount granted"}
    }
  }

  @progress_schema %Schema{
    type: :object,
    nullable: true,
    properties: %{
      period_key: %Schema{
        type: :string,
        description: "Reset bucket (\"static\", date or ISO week)"
      },
      objective_progress: %Schema{
        type: :object,
        description: "Objective index (string) to current count"
      },
      status: %Schema{type: :string, enum: ["active", "completed", "claimed"]},
      completed_at: %Schema{type: :string, format: "date-time", nullable: true},
      claimed_at: %Schema{type: :string, format: "date-time", nullable: true}
    }
  }

  @quest_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Quest ID"},
      key: %Schema{type: :string, description: "Unique slug"},
      title: %Schema{type: :string, description: "Display title"},
      description: %Schema{type: :string, description: "Description"},
      icon_url: %Schema{type: :string, description: "Icon URL"},
      sort_order: %Schema{type: :integer, description: "Display order"},
      hidden: %Schema{type: :boolean, description: "Whether hidden until completed"},
      reset: %Schema{
        type: :string,
        enum: ["never", "daily", "weekly", "monthly", "interval"],
        description: "When progress starts over"
      },
      reset_interval_days: %Schema{
        type: :integer,
        nullable: true,
        description: "Cadence in days when reset is \"interval\" (biweekly = 14)"
      },
      category: %Schema{
        type: :string,
        nullable: true,
        description: "Free-form grouping label for your UI (no engine behavior)"
      },
      objectives: %Schema{type: :array, items: @objective_schema},
      rewards: %Schema{type: :array, items: @reward_schema},
      auto_claim: %Schema{type: :boolean, description: "Rewards grant on completion"},
      prerequisite_quest_key: %Schema{
        type: :string,
        nullable: true,
        description: "Quest key that must be completed first"
      },
      starts_at: %Schema{type: :string, format: "date-time", nullable: true},
      ends_at: %Schema{type: :string, format: "date-time", nullable: true},
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      progress: @progress_schema,
      claimable: %Schema{type: :boolean, description: "Completed and waiting to be claimed"}
    },
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      key: "daily_win_3",
      title: "Win 3 matches",
      description: "Win three matches today",
      icon_url: "",
      sort_order: 0,
      hidden: false,
      reset: "daily",
      reset_interval_days: nil,
      category: "daily",
      objectives: [%{event: "match_won", target: 3, params: %{}}],
      rewards: [%{type: "currency", code: "gold", amount: 100}],
      auto_claim: false,
      prerequisite_quest_key: nil,
      starts_at: nil,
      ends_at: nil,
      metadata: %{},
      progress: %{
        period_key: "2026-07-24",
        objective_progress: %{"0" => 1},
        status: "active",
        completed_at: nil,
        claimed_at: nil
      },
      claimable: false
    }
  }

  @meta_schema %Schema{
    type: :object,
    properties: %{
      page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      count: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer},
      has_more: %Schema{type: :boolean}
    }
  }

  # ---------------------------------------------------------------------------
  # GET /api/v1/me/quests
  # ---------------------------------------------------------------------------

  operation(:me,
    operation_id: "my_quests",
    summary: "List my quests",
    description:
      "List active quests with the authenticated user's progress for the current " <>
        "reset period and a claimable flag. Hidden quests appear once completed; " <>
        "chain quests appear once their prerequisite is met.",
    parameters: [
      category: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: %{
      200 =>
        {"Quest list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @quest_schema},
             meta: @meta_schema
           }
         }},
      401 => {"Unauthorized", "application/json", %Schema{type: :object}}
    }
  )

  def me(conn, params) do
    case conn.assigns[:current_scope] do
      %{user_id: user_id} ->
        {page, page_size} = Pagination.params(params)
        opts = [page: page, page_size: page_size, category: params["category"]]

        entries = Quests.list_user_quests(user_id, opts)
        total_count = Quests.count_user_quests(user_id, category: params["category"])

        json(conn, %{
          data: Enum.map(entries, &serialize_entry/1),
          meta: Pagination.meta(page, page_size, length(entries), total_count)
        })

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/me/quests/:key/claim
  # ---------------------------------------------------------------------------

  operation(:claim,
    operation_id: "claim_quest",
    summary: "Claim a completed quest",
    description:
      "Claim the rewards of a completed quest for the current reset period. " <>
        "Claiming is exactly-once: a repeated or concurrent claim returns " <>
        "already_claimed and never double-pays.",
    parameters: [
      key: [in: :path, schema: %Schema{type: :string}, required: true]
    ],
    responses: %{
      200 =>
        {"Claimed", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 progress: @progress_schema,
                 rewards: %Schema{type: :array, items: @reward_schema}
               }
             }
           }
         }},
      401 => {"Unauthorized", "application/json", %Schema{type: :object}},
      404 => {"Not found", "application/json", %Schema{type: :object}},
      409 => {"Not claimable", "application/json", %Schema{type: :object}}
    }
  )

  def claim(conn, %{"key" => key}) do
    case conn.assigns[:current_scope] do
      %{user_id: user_id} ->
        case Quests.claim(user_id, key) do
          {:ok, %{progress: progress, rewards: rewards}} ->
            json(conn, %{
              data: %{
                progress: serialize_progress(progress),
                rewards: Enum.map(rewards, &serialize_reward/1)
              }
            })

          {:error, :quest_not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "quest_not_found"})

          {:error, :not_completed} ->
            conn |> put_status(:conflict) |> json(%{error: "not_completed"})

          {:error, :already_claimed} ->
            conn |> put_status(:conflict) |> json(%{error: "already_claimed"})

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "claim_rejected", reason: inspect(reason)})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/quests (catalog, gated)
  # ---------------------------------------------------------------------------

  operation(:index,
    operation_id: "list_quests",
    summary: "List quests",
    description:
      "Public quest catalog: active, in-window quest definitions. If authenticated, " <>
        "includes user progress (same shape as /me/quests).",
    parameters: [
      category: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: %{
      200 =>
        {"Quest list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @quest_schema},
             meta: @meta_schema
           }
         }}
    }
  )

  def index(conn, params) do
    case conn.assigns[:current_scope] do
      %{user_id: _} ->
        me(conn, params)

      _ ->
        {page, page_size} = Pagination.params(params)
        now = DateTime.utc_now(:second)

        visible =
          Quests.active_quests()
          |> Enum.filter(fn q ->
            within_window?(q, now) and params["category"] in [nil, q.category]
          end)

        entries =
          visible
          |> Enum.drop((page - 1) * page_size)
          |> Enum.take(page_size)
          |> Enum.map(fn quest -> %{quest: quest, progress: nil, claimable: false} end)

        json(conn, %{
          data: Enum.map(entries, &serialize_entry/1),
          meta: Pagination.meta(page, page_size, length(entries), length(visible))
        })
    end
  end

  defp within_window?(quest, now) do
    (is_nil(quest.starts_at) or DateTime.compare(quest.starts_at, now) != :gt) and
      (is_nil(quest.ends_at) or DateTime.compare(quest.ends_at, now) == :gt)
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/quests/user/:user_id (public completions, gated)
  # ---------------------------------------------------------------------------

  operation(:user_quests,
    operation_id: "user_quests",
    summary: "List a user's completed quests",
    description:
      "Publicly visible completions for a specific user, newest first — " <>
        "defaults to category \"achievement\" (the replacement for the old " <>
        "/achievements/user/:user_id endpoint). Hidden quests appear once earned.",
    parameters: [
      user_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      category: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: %{
      200 =>
        {"Completed quests", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @quest_schema},
             meta: @meta_schema
           }
         }},
      400 => {"Invalid user id", "application/json", %Schema{type: :object}}
    }
  )

  def user_quests(conn, %{"user_id" => user_id_str} = params) do
    case Ecto.UUID.cast(user_id_str) do
      {:ok, user_id} ->
        {page, page_size} = Pagination.params(params)
        category = params["category"] || "achievement"
        opts = [page: page, page_size: page_size, category: category]

        entries = Quests.list_user_completions(user_id, opts)
        total_count = Quests.count_user_completions(user_id, category: category)

        json(conn, %{
          data:
            Enum.map(entries, fn %{quest: quest, progress: progress} ->
              serialize_entry(%{quest: quest, progress: progress, claimable: false})
            end),
          meta: Pagination.meta(page, page_size, length(entries), total_count)
        })

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_user_id"})
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_entry(%{quest: quest, progress: progress, claimable: claimable}) do
    completed? = progress != nil and progress.status in ["completed", "claimed"]

    base =
      if quest.hidden and not completed? do
        # Hidden + not completed: obscure all details
        %{
          id: quest.id,
          key: quest.key,
          title: "???",
          description: "???",
          icon_url: "",
          sort_order: quest.sort_order,
          hidden: true,
          reset: quest.reset,
          reset_interval_days: quest.reset_interval_days,
          category: quest.category || "",
          objectives: [],
          rewards: [],
          auto_claim: quest.auto_claim,
          prerequisite_quest_key: quest.prerequisite_quest_key || "",
          starts_at: quest.starts_at,
          ends_at: quest.ends_at,
          metadata: %{}
        }
      else
        %{
          id: quest.id,
          key: quest.key,
          title: quest.title,
          description: quest.description || "",
          icon_url: quest.icon_url || "",
          sort_order: quest.sort_order,
          hidden: quest.hidden,
          reset: quest.reset,
          reset_interval_days: quest.reset_interval_days,
          category: quest.category || "",
          objectives: Enum.map(quest.objectives, &serialize_objective/1),
          rewards: Enum.map(quest.rewards, &serialize_reward/1),
          auto_claim: quest.auto_claim,
          prerequisite_quest_key: quest.prerequisite_quest_key || "",
          starts_at: quest.starts_at,
          ends_at: quest.ends_at,
          metadata: quest.metadata || %{}
        }
      end

    Map.merge(base, %{progress: serialize_progress(progress), claimable: claimable})
  end

  defp serialize_objective(objective) do
    %{event: objective.event, target: objective.target, params: objective.params || %{}}
  end

  defp serialize_reward(reward) do
    %{type: reward.type, code: reward.code, amount: reward.amount}
  end

  defp serialize_progress(nil), do: nil

  defp serialize_progress(progress) do
    %{
      period_key: progress.period_key,
      objective_progress: progress.objective_progress,
      status: progress.status,
      completed_at: progress.completed_at,
      claimed_at: progress.claimed_at
    }
  end
end
