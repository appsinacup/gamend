defmodule GameServerWeb.Api.V1.Admin.ReadyCheckController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.ReadyChecks
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Admin – Ready checks"])

  @check_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string, enum: ["ready", "accept"]},
      status: %Schema{type: :string, enum: ["pending", "passed", "failed", "cancelled"]},
      lobby_id: %Schema{type: :string, format: :uuid, nullable: true},
      deadline_at: %Schema{type: :string, format: "date-time", nullable: true},
      opened_by: %Schema{type: :string, format: :uuid, nullable: true},
      reason: %Schema{type: :string},
      resolved_at: %Schema{type: :string, format: "date-time", nullable: true},
      participants: %Schema{type: :array, items: %Schema{type: :object}}
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

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  operation(:index,
    operation_id: "admin_list_ready_checks",
    summary: "List ready checks (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      status: [
        in: :query,
        schema: %Schema{type: :string, enum: ["pending", "passed", "failed", "cancelled"]},
        required: false
      ],
      kind: [
        in: :query,
        schema: %Schema{type: :string, enum: ["ready", "accept"]},
        required: false
      ],
      lobby_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok:
        {"Ready checks", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @check_schema},
             meta: @meta_schema
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def index(conn, params) do
    {page, page_size} = GameServerWeb.Pagination.params(params)

    filters = [
      status: params["status"],
      kind: params["kind"],
      lobby_id: params["lobby_id"],
      page: page,
      page_size: page_size
    ]

    checks = ReadyChecks.list_checks(filters)
    total = ReadyChecks.count_checks(filters)

    json(conn, %{
      data: Enum.map(checks, &serialize/1),
      meta: Pagination.meta(page, page_size, length(checks), total)
    })
  end

  operation(:delete,
    operation_id: "admin_cancel_ready_check",
    summary: "Force-cancel a pending ready check (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok:
        {"Cancelled", "application/json",
         %Schema{type: :object, properties: %{data: @check_schema}}},
      not_found: {"Unknown or already resolved", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"id" => id}) do
    with %{status: "pending"} = check <- ReadyChecks.get_check(id),
         {:ok, cancelled} <- ReadyChecks.cancel(check) do
      json(conn, %{data: serialize(cancelled)})
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  operation(:stats,
    operation_id: "admin_ready_check_stats",
    summary: "Ready check outcomes over the last 24 hours (admin)",
    description:
      "Counts by status — the accept rate and dodge rate of the queue and of lobby starts.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Stats", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def stats(conn, _params) do
    json(conn, %{data: ReadyChecks.stats()})
  end

  defp serialize(check) do
    %{
      id: check.id,
      kind: check.kind,
      status: check.status,
      lobby_id: check.lobby_id,
      deadline_at: check.deadline_at,
      opened_by: check.opened_by,
      reason: check.reason || "",
      resolved_at: check.resolved_at,
      inserted_at: check.inserted_at,
      participants: Enum.map(check.participants, &serialize_participant/1)
    }
  end

  defp serialize_participant(participant) do
    %{
      user_id: participant.user_id,
      state: participant.state,
      responded_at: participant.responded_at
    }
  end
end
