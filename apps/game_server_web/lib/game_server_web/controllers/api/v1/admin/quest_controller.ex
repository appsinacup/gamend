defmodule GameServerWeb.Api.V1.Admin.QuestController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Quests
  alias GameServerWeb.Pagination
  alias GameServerWeb.Uploads
  alias OpenApiSpex.Schema

  tags(["Admin – Quests"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @quest_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      key: %Schema{type: :string},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{type: :string},
      sort_order: %Schema{type: :integer},
      hidden: %Schema{type: :boolean},
      reset: %Schema{type: :string, enum: ["never", "daily", "weekly", "monthly", "interval"]},
      reset_interval_days: %Schema{type: :integer, nullable: true},
      category: %Schema{type: :string},
      objectives: %Schema{type: :array, items: %Schema{type: :object}},
      rewards: %Schema{type: :array, items: %Schema{type: :object}},
      auto_claim: %Schema{type: :boolean},
      prerequisite_quest_key: %Schema{type: :string},
      starts_at: %Schema{type: :string, format: "date-time", nullable: true},
      ends_at: %Schema{type: :string, format: "date-time", nullable: true},
      active: %Schema{type: :boolean},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    }
  }

  @progress_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      quest_key: %Schema{type: :string},
      period_key: %Schema{type: :string},
      objective_progress: %Schema{type: :object},
      status: %Schema{type: :string, enum: ["active", "completed", "claimed"]},
      completed_at: %Schema{type: :string, format: "date-time", nullable: true},
      claimed_at: %Schema{type: :string, format: "date-time", nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    }
  }

  @quest_body_schema %Schema{
    type: :object,
    properties: %{
      key: %Schema{type: :string},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{type: :string},
      sort_order: %Schema{type: :integer},
      hidden: %Schema{type: :boolean},
      reset: %Schema{type: :string, enum: ["never", "daily", "weekly", "monthly", "interval"]},
      reset_interval_days: %Schema{type: :integer, nullable: true},
      category: %Schema{type: :string},
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
    responses: %{
      200 =>
        {"Quest list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @quest_schema},
             meta: %Schema{type: :object}
           }
         }}
    }
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

    json(conn, Pagination.envelope(quests, page, page_size, total_count))
  end

  # ---------------------------------------------------------------------------
  # CREATE / UPDATE / DELETE
  # ---------------------------------------------------------------------------

  operation(:create,
    operation_id: "admin_create_quest",
    summary: "Create quest (admin)",
    security: [%{"authorization" => []}],
    request_body: {"Quest", "application/json", @quest_body_schema},
    responses: %{
      201 => {"Created", "application/json", @quest_schema},
      422 => {"Validation error", "application/json", @error_schema}
    }
  )

  def create(conn, params) do
    case Quests.create_quest(params) do
      {:ok, quest} ->
        conn |> put_status(:created) |> json(%{data: quest})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
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
    responses: %{
      200 => {"Updated", "application/json", @quest_schema},
      404 => {"Not found", "application/json", @error_schema},
      422 => {"Validation error", "application/json", @error_schema}
    }
  )

  def update(conn, %{"id" => id} = params) do
    with_quest(conn, id, fn quest ->
      case Quests.update_quest(quest, Map.delete(params, "id")) do
        {:ok, updated} -> json(conn, %{data: updated})
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
      ok: {"Upload ticket", "application/json", %Schema{type: :object}},
      bad_request: {"Unsupported content type", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def icon_upload_url(conn, %{"id" => id} = params) do
    with_quest(conn, id, fn quest ->
      Uploads.ticket(conn, "icons/quests", quest.id, "icon", Uploads.content_type(params))
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
      ok: {"Updated quest", "application/json", %Schema{type: :object}},
      bad_request: {"Object not found", "application/json", @error_schema},
      forbidden: {"Key not owned by this quest", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def set_icon(conn, %{"id" => id} = params) do
    with_quest(conn, id, fn quest ->
      Uploads.confirm(conn, "icons/quests", quest.id, params["key"], fn url ->
        case Quests.update_quest(quest, %{"icon_url" => url}) do
          {:ok, updated} -> json(conn, %{data: updated})
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
    responses: %{
      200 => {"Deleted", "application/json", %Schema{type: :object}},
      404 => {"Not found", "application/json", @error_schema}
    }
  )

  def delete(conn, %{"id" => id}) do
    case Quests.get_quest(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      quest ->
        case Quests.delete_quest(quest) do
          {:ok, _} ->
            json(conn, %{data: %{deleted: true}})

          {:error, _} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "delete_failed"})
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
    responses: %{
      200 =>
        {"Progress list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @progress_schema},
             meta: %Schema{type: :object}
           }
         }}
    }
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

    json(conn, Pagination.envelope(rows, page, page_size, total_count))
  end

  operation(:grant,
    operation_id: "admin_grant_quest",
    summary: "Force-complete a quest for a user (admin)",
    description:
      "Every objective jumps to its target for the current period; completion hooks " <>
        "fire and auto-claim quests pay out immediately.",
    security: [%{"authorization" => []}],
    request_body: {"Grant", "application/json", @user_quest_body},
    responses: %{
      200 => {"Granted", "application/json", @progress_schema},
      404 => {"Not found", "application/json", @error_schema},
      409 => {"Already completed", "application/json", @error_schema}
    }
  )

  def grant(conn, %{"user_id" => user_id, "key" => key}) do
    case Quests.admin_complete(user_id, key) do
      {:ok, progress} ->
        json(conn, %{data: progress})

      {:error, :quest_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "quest_not_found"})

      {:error, :already_completed} ->
        conn |> put_status(:conflict) |> json(%{error: "already_completed"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def grant(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "user_id and key required"})
  end

  operation(:reset,
    operation_id: "admin_reset_quest",
    summary: "Reset a user's current-period quest progress (admin)",
    security: [%{"authorization" => []}],
    request_body: {"Reset", "application/json", @user_quest_body},
    responses: %{
      200 => {"Reset", "application/json", %Schema{type: :object}},
      404 => {"Not found", "application/json", @error_schema}
    }
  )

  def reset(conn, %{"user_id" => user_id, "key" => key}) do
    case Quests.admin_reset(user_id, key) do
      {:ok, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "no_progress"})

      {:ok, _} ->
        json(conn, %{data: %{reset: true}})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def reset(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "user_id and key required"})
  end

  operation(:claim,
    operation_id: "admin_claim_quest",
    summary: "Claim a completed quest on a user's behalf (admin)",
    description: "Skips the before_quest_claim veto. Reward grants stay exactly-once.",
    security: [%{"authorization" => []}],
    request_body: {"Claim", "application/json", @user_quest_body},
    responses: %{
      200 => {"Claimed", "application/json", %Schema{type: :object}},
      404 => {"Not found", "application/json", @error_schema},
      409 => {"Not claimable", "application/json", @error_schema}
    }
  )

  def claim(conn, %{"user_id" => user_id, "key" => key}) do
    case Quests.admin_claim(user_id, key) do
      {:ok, %{progress: progress, rewards: rewards}} ->
        json(conn, %{data: %{progress: progress, rewards: rewards}})

      {:error, :quest_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "quest_not_found"})

      {:error, :not_completed} ->
        conn |> put_status(:conflict) |> json(%{error: "not_completed"})

      {:error, :already_claimed} ->
        conn |> put_status(:conflict) |> json(%{error: "already_claimed"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def claim(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "user_id and key required"})
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
    responses: %{
      200 => {"Funnel", "application/json", %Schema{type: :object}}
    }
  )

  def funnel(conn, %{"key" => key}) do
    json(conn, %{data: Quests.funnel(key)})
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp with_quest(conn, id, fun) do
    case Quests.get_quest(id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
      quest -> fun.(quest)
    end
  end

  defp changeset_error(conn, changeset) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(changeset)})
  end
end
