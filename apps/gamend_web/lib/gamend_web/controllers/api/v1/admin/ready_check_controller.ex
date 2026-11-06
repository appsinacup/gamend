defmodule GamendWeb.Api.V1.Admin.ReadyCheckController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.ReadyChecks
  alias Gamend.ReadyChecks.Check
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    AdminReadyCheckPage,
    AdminReadyCheckResponse,
    ReadyCheckOutcomesResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – Ready checks"])

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
      ok: {"Ready checks", "application/json", AdminReadyCheckPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def index(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)

    filters = [
      status: params["status"],
      kind: params["kind"],
      lobby_id: params["lobby_id"],
      page: page,
      page_size: page_size
    ]

    checks = ReadyChecks.list_checks(filters)
    total = ReadyChecks.count_checks(filters)

    reply_page(conn, Enum.map(checks, &serialize/1), page, page_size, total)
  end

  operation(:delete,
    operation_id: "admin_cancel_ready_check",
    summary: "Force-cancel a pending ready check (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Cancelled", "application/json", AdminReadyCheckResponse},
      not_found: Schemas.error("Unknown id"),
      conflict: Schemas.error("Passed, failed or cancelled already (already_resolved)"),
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  # `cancel/1` decides under the check's lock whether it is still pending: a
  # check that passed, failed or was cancelled is `already_resolved` (409), one
  # deleted with its subject `no_open_check` (404).
  def delete(conn, %{"id" => id}) do
    with %Check{} = check <- ReadyChecks.get_check(id),
         {:ok, cancelled} <- ReadyChecks.cancel(check) do
      reply_data(conn, serialize(cancelled))
    else
      nil -> reply_error(conn, :not_found, "not_found")
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  operation(:stats,
    operation_id: "admin_ready_check_stats",
    summary: "Ready check outcomes over the last 24 hours (admin)",
    description:
      "Counts by status — the accept rate and dodge rate of the queue and of lobby starts.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Stats", "application/json", ReadyCheckOutcomesResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def stats(conn, _params) do
    reply_data(conn, ReadyChecks.stats())
  end

  defp serialize(check) do
    %{
      id: check.id,
      kind: check.kind,
      status: check.status,
      lobby_id: check.lobby_id || "",
      party_id: check.party_id || "",
      deadline_at: check.deadline_at,
      opened_by: check.opened_by || "",
      reason: check.reason || "",
      resolved_at: check.resolved_at,
      inserted_at: check.inserted_at,
      participants: Enum.map(check.participants, &serialize_participant/1)
    }
  end

  defp serialize_participant(participant) do
    %{
      user_id: participant.user_id,
      display_name: Serializers.display_name(participant.user_id),
      state: participant.state,
      responded_at: participant.responded_at
    }
  end
end
