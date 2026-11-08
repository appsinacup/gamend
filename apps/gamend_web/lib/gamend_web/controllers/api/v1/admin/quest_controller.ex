defmodule GamendWeb.Api.V1.Admin.QuestController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Quests
  alias Gamend.Quests.Quest
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    AdminQuestClaimResponse,
    AdminQuestPage,
    AdminQuestProgressPage,
    AdminQuestProgressResponse,
    AdminQuestResponse,
    OkResponse,
    QuestFunnelResponse,
    UploadTicketResponse
  }

  alias GamendWeb.Serializers
  alias GamendWeb.Uploads
  alias OpenApiSpex.Schema

  require GamendWeb.UploadName, as: UploadName

  tags(["Admin – Quests"])

  @quest_body_schema %Schema{
    type: :object,
    properties: %{
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
      objectives: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            event: %Schema{type: :string},
            target: %Schema{type: :integer},
            params: %Schema{type: :object}
          },
          required: [:event]
        }
      },
      rewards: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            type: %Schema{type: :string, enum: ["currency", "item"]},
            code: %Schema{type: :string},
            amount: %Schema{type: :integer}
          },
          required: [:type, :code]
        }
      },
      auto_claim: %Schema{type: :boolean},
      prerequisite_quest_key: %Schema{type: :string},
      starts_at: %Schema{type: :string, format: "date-time", nullable: true},
      ends_at: %Schema{type: :string, format: "date-time", nullable: true},
      active: %Schema{type: :boolean},
      metadata: %Schema{type: :object}
    }
  }

  @user_quest_body %Schema{
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      key: %Schema{type: :string, description: "Quest key"}
    },
    required: [:user_id, :key]
  }

  # ---------------------------------------------------------------------------
  # INDEX
  # ---------------------------------------------------------------------------

  operation(:index,
    operation_id: "admin_list_quests",
    summary: "List all quest definitions (admin, includes inactive/hidden)",
    security: [%{"authorization" => []}],
    parameters: [
      category: [in: :query, schema: %Schema{type: :string}, required: false],
      search: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [
      ok: {"Quests", "application/json", AdminQuestPage}
    ]
  )

  def index(conn, params) do
    {page, page_size} = Pagination.params(params)

    opts = [
      page: page,
      page_size: page_size,
      category: params["category"],
      search: params["search"]
    ]

    quests = Quests.list_quests(opts)
    total_count = Quests.count_quests(category: params["category"], search: params["search"])

    reply_page(conn, Enum.map(quests, &serialize_quest/1), page, page_size, total_count)
  end

  # ---------------------------------------------------------------------------
  # CREATE / UPDATE / DELETE
  # ---------------------------------------------------------------------------

  operation(:create,
    operation_id: "admin_create_quest",
    summary: "Create quest (admin)",
    security: [%{"authorization" => []}],
    request_body: {"Quest", "application/json", @quest_body_schema},
    responses: [
      created: {"Created", "application/json", AdminQuestResponse},
      forbidden: Schemas.error("At the max_quests limit (quest_limit_reached)"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def create(conn, params) do
    case Quests.create_quest(params) do
      {:ok, quest} ->
        reply_data(conn, :created, serialize_quest(quest))

      {:error, reason} ->
        failure(conn, reason)
    end
  end

  operation(:update,
    operation_id: "admin_update_quest",
    summary: "Update quest (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {"Quest", "application/json", @quest_body_schema},
    responses: [
      ok: {"Updated", "application/json", AdminQuestResponse},
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def update(conn, %{"id" => id} = params) do
    with_quest(conn, id, fn quest ->
      case Quests.update_quest(quest, Map.delete(params, "id")) do
        {:ok, updated} -> reply_data(conn, serialize_quest(updated))
        {:error, %Ecto.Changeset{} = changeset} -> changeset_error(conn, changeset)
      end
    end)
  end

  operation(:icon_upload_url,
    operation_id: "admin_quest_icon_upload_url",
    summary: "Request an upload ticket for a quest icon (admin)",
    description: """
    Step one of two. Returns a presigned ticket; PUT the image straight to
    `url`, then POST the returned `key` to the icon endpoint. Bytes never pass
    through the app server.
    """,
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    request_body:
      {"Declared content type", "application/json",
       %Schema{
         type: :object,
         properties: %{content_type: %Schema{type: :string, example: "image/png"}},
         required: [:content_type]
       }},
    responses: [
      ok: {"Upload ticket", "application/json", UploadTicketResponse},
      bad_request: Schemas.error("Unsupported content type"),
      not_found: Schemas.error("Not found")
    ]
  )

  def icon_upload_url(conn, %{"id" => id} = params) do
    with_quest(conn, id, fn quest ->
      Uploads.ticket(
        conn,
        "icons/quests",
        quest.id,
        UploadName.icon(),
        Uploads.content_type(params)
      )
    end)
  end

  operation(:set_icon,
    operation_id: "admin_set_quest_icon",
    summary: "Confirm an uploaded quest icon (admin)",
    description: "Step two: records a previously uploaded object as the icon.",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    request_body:
      {"Uploaded object key", "application/json",
       %Schema{type: :object, properties: %{key: %Schema{type: :string}}, required: [:key]}},
    responses: [
      ok: {"Updated quest", "application/json", AdminQuestResponse},
      bad_request: Schemas.error("Object not found"),
      forbidden: Schemas.error("Key not owned by this quest"),
      not_found: Schemas.error("Not found")
    ]
  )

  def set_icon(conn, %{"id" => id} = params) do
    with_quest(conn, id, fn quest ->
      Uploads.confirm(conn, "icons/quests", quest.id, params["key"], fn url ->
        case Quests.update_quest(quest, %{"icon_url" => url}) do
          {:ok, updated} -> reply_data(conn, serialize_quest(updated))
          {:error, %Ecto.Changeset{} = changeset} -> changeset_error(conn, changeset)
        end
      end)
    end)
  end

  operation(:delete,
    operation_id: "admin_delete_quest",
    summary: "Delete quest and all user progress (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Could not delete (validation_failed)")
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Quests.get_quest(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      quest ->
        case Quests.delete_quest(quest) do
          {:ok, _} ->
            reply_ok(conn)

          {:error, %Ecto.Changeset{} = changeset} ->
            changeset_error(conn, changeset)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # PROGRESS (list / grant / reset / force-claim)
  # ---------------------------------------------------------------------------

  operation(:progress,
    operation_id: "admin_list_quest_progress",
    summary: "List quest progress rows (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [
        in: :query,
        schema: %Schema{type: :string},
        required: false,
        description: "User UUID or username/display-name substring"
      ],
      quest_key: [in: :query, schema: %Schema{type: :string}, required: false],
      status: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [
      ok: {"Progress rows", "application/json", AdminQuestProgressPage}
    ]
  )

  def progress(conn, params) do
    {page, page_size} = Pagination.params(params)

    opts = [
      page: page,
      page_size: page_size,
      user_id: params["user_id"],
      quest_key: params["quest_key"],
      status: params["status"]
    ]

    rows = Quests.list_progress(opts)
    total_count = Quests.count_progress(opts)

    reply_page(
      conn,
      Enum.map(rows, &Serializers.serialize_quest_progress/1),
      page,
      page_size,
      total_count
    )
  end

  operation(:grant,
    operation_id: "admin_grant_quest",
    summary: "Force-complete a quest for a user (admin)",
    description:
      "Every objective jumps to its target for the current period; completion hooks " <>
        "fire and auto-claim quests pay out immediately.",
    security: [%{"authorization" => []}],
    request_body: {"Grant", "application/json", @user_quest_body},
    responses: [
      ok: {"Granted", "application/json", AdminQuestProgressResponse},
      bad_request: Schemas.error("user_id and key are required (missing_param)"),
      not_found: Schemas.error("No quest with that key"),
      conflict:
        Schemas.error(
          "Already completed (already_completed), or every retry lost to the player's own " <>
            "progress (contended)"
        )
    ]
  )

  def grant(conn, %{"user_id" => user_id, "key" => key}) do
    case Quests.admin_complete(user_id, key) do
      {:ok, progress} ->
        reply_data(conn, Serializers.serialize_quest_progress(progress))

      {:error, :quest_not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, :already_completed} ->
        reply_error(conn, :conflict, "already_completed")

      {:error, reason} ->
        failure(conn, reason)
    end
  end

  def grant(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "user_id and key are required")
  end

  operation(:reset,
    operation_id: "admin_reset_quest",
    summary: "Reset a user's current-period quest progress (admin)",
    security: [%{"authorization" => []}],
    request_body: {"Reset", "application/json", @user_quest_body},
    responses: [
      ok: {"Reset", "application/json", OkResponse},
      bad_request: Schemas.error("user_id and key are required (missing_param)"),
      not_found: Schemas.error("No progress to reset (no_progress)")
    ]
  )

  def reset(conn, %{"user_id" => user_id, "key" => key}) do
    case Quests.admin_reset(user_id, key) do
      {:ok, :not_found} ->
        reply_error(conn, :not_found, "no_progress")

      {:ok, _} ->
        reply_ok(conn)

      {:error, reason} ->
        failure(conn, reason)
    end
  end

  def reset(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "user_id and key are required")
  end

  operation(:claim,
    operation_id: "admin_claim_quest",
    summary: "Claim a completed quest on a user's behalf (admin)",
    description: "Skips the before_quest_claim veto. Reward grants stay exactly-once.",
    security: [%{"authorization" => []}],
    request_body: {"Claim", "application/json", @user_quest_body},
    responses: [
      ok: {"Claimed", "application/json", AdminQuestClaimResponse},
      bad_request: Schemas.error("user_id and key are required (missing_param)"),
      forbidden:
        Schemas.error(
          "Not completed (not_completed), or a guest where claims need an account " <>
            "(account_required)"
        ),
      not_found: Schemas.error("No quest with that key"),
      conflict: Schemas.error("Already claimed (already_claimed)")
    ]
  )

  def claim(conn, %{"user_id" => user_id, "key" => key}) do
    case Quests.admin_claim(user_id, key) do
      {:ok, %{progress: progress, rewards: rewards}} ->
        reply_data(conn, %{
          progress: Serializers.serialize_quest_progress(progress),
          rewards: Enum.map(rewards, &serialize_reward/1)
        })

      {:error, :quest_not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, :not_completed} ->
        reply_error(conn, :forbidden, "not_completed")

      {:error, :already_claimed} ->
        reply_error(conn, :conflict, "already_claimed")

      {:error, reason} ->
        failure(conn, reason)
    end
  end

  def claim(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "user_id and key are required")
  end

  # ---------------------------------------------------------------------------
  # FUNNEL
  # ---------------------------------------------------------------------------

  operation(:funnel,
    operation_id: "admin_quest_funnel",
    summary: "Per-status progress counts for one quest (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      key: [in: :path, schema: %Schema{type: :string}, required: true]
    ],
    responses: [
      ok: {"Funnel", "application/json", QuestFunnelResponse}
    ]
  )

  def funnel(conn, %{"key" => key}) do
    reply_data(conn, Quests.funnel(key))
  end

  defp with_quest(conn, id, fun) do
    case Quests.get_quest(id) do
      nil -> reply_error(conn, :not_found, "not_found")
      quest -> fun.(quest)
    end
  end

  defp changeset_error(conn, changeset) do
    unprocessable(conn, changeset)
  end

  # A changeset is a validation failure. `Gamend.Quests`' other reasons take
  # their status from `GamendWeb.ErrorStatus`: `quest_limit_reached` and
  # `account_required` 403, `contended` 409 (a grant that lost every retry
  # to the player's own progress).
  defp failure(conn, %Ecto.Changeset{} = changeset), do: unprocessable(conn, changeset)
  defp failure(conn, reason), do: reply_reason(conn, reason)

  defp serialize_quest(%Quest{} = quest) do
    %{
      id: quest.id,
      key: quest.key,
      title: quest.title || "",
      description: quest.description || "",
      icon_url: quest.icon_url || "",
      sort_order: quest.sort_order,
      hidden: quest.hidden,
      reset: quest.reset,
      reset_interval_days: quest.reset_interval_days,
      category: quest.category || "",
      group_key: quest.group_key || "",
      group_title: quest.group_title || "",
      objectives: Enum.map(quest.objectives || [], &serialize_objective/1),
      rewards: Enum.map(quest.rewards || [], &serialize_reward/1),
      auto_claim: quest.auto_claim,
      prerequisite_quest_key: quest.prerequisite_quest_key || "",
      starts_at: quest.starts_at,
      ends_at: quest.ends_at,
      active: quest.active,
      metadata: quest.metadata || %{},
      inserted_at: quest.inserted_at,
      updated_at: quest.updated_at
    }
  end

  defp serialize_objective(objective),
    do: %{event: objective.event, target: objective.target, params: objective.params || %{}}

  defp serialize_reward(reward),
    do: %{type: reward.type, code: reward.code, amount: reward.amount}
end
