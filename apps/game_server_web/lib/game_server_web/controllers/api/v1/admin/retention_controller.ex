defmodule GameServerWeb.Api.V1.Admin.RetentionController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Retention
  alias OpenApiSpex.Schema

  tags(["Admin – Retention"])

  @status_schema %Schema{
    type: :object,
    properties: %{
      last_run_at: %Schema{type: :string, format: "date-time", nullable: true},
      duration_ms: %Schema{type: :integer, nullable: true},
      results: %Schema{
        type: :object,
        description: "Rows pruned per class in the last sweep",
        additionalProperties: %Schema{type: :integer}
      }
    }
  }

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  operation(:show,
    operation_id: "admin_get_retention_status",
    summary: "Last retention sweep (admin)",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Status", "application/json", @status_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def show(conn, _params), do: json(conn, serialize(Retention.status()))

  operation(:run,
    operation_id: "admin_run_retention",
    summary: "Run a retention sweep now (admin)",
    description:
      "Sweeps immediately instead of waiting for the next 6h cycle. Runs inside " <>
        "the sweeper, so it can never overlap the scheduled run.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Status", "application/json", @status_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      service_unavailable: {"Sweeper not running", "application/json", @error_schema}
    ]
  )

  def run(conn, _params) do
    _results = Retention.run_now()
    json(conn, serialize(Retention.status()))
  catch
    :exit, _reason ->
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "retention sweeper is not running"})
  end

  defp serialize(status) do
    %{
      last_run_at: status.last_run_at,
      duration_ms: status.duration_ms,
      results: Map.new(status.results, fn {class, count} -> {to_string(class), count} end)
    }
  end
end
