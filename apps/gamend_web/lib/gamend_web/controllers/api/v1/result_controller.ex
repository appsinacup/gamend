defmodule GamendWeb.Api.V1.ResultController do
  @moduledoc """
  The caller's results over HTTP (`GamendWeb.ResultReads`): the same reads
  the user socket answers (`results:list`, `results:get`, `results:events`),
  for a client that has no socket yet.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Results.ResultStatus
  alias GamendWeb.ResultReads
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{PlayResultEventsResponse, PlayResultPage, PlayResultResponse}
  alias OpenApiSpex.Schema

  tags(["Results"])

  operation(:index,
    operation_id: "list_results",
    summary: "List the caller's results",
    description: "The caller's plays, newest first, each with its stats by event key.",
    security: [%{"authorization" => []}],
    parameters: [
      kind: [in: :query, schema: %Schema{type: :string}, required: false],
      status: [
        in: :query,
        schema: %Schema{type: :string, enum: ResultStatus.all()},
        required: false
      ],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok: {"The caller's results", "application/json", PlayResultPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def index(conn, params) do
    {rows, page, page_size, total} = ResultReads.page(caller_id(conn), params)
    reply_page(conn, rows, page, page_size, total)
  end

  operation(:show,
    operation_id: "get_result",
    summary: "Get a result",
    description: "One result and its stats, under its visibility.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"The result", "application/json", PlayResultResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("The caller's own result, hidden from clients"),
      not_found: Schemas.error("No result the caller may read")
    ]
  )

  def show(conn, %{"id" => id}) do
    conn |> answer(ResultReads.get(caller_id(conn), id))
  end

  operation(:events,
    operation_id: "list_result_events",
    summary: "List a result's events",
    description:
      "A result's events, oldest first. `after` is an event id: the events written since it.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      after: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      limit: [in: :query, schema: %Schema{type: :integer, default: 500}, required: false]
    ],
    responses: [
      ok: {"The events", "application/json", PlayResultEventsResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("The caller's own result, hidden from clients"),
      not_found: Schemas.error("No result the caller may read")
    ]
  )

  def events(conn, %{"id" => id} = params) do
    conn |> answer(ResultReads.events(caller_id(conn), id, params))
  end

  defp answer(conn, {:ok, data}), do: reply_data(conn, data)
  defp answer(conn, {:error, :forbidden}), do: reply_error(conn, :forbidden, "forbidden")
  defp answer(conn, {:error, :not_found}), do: reply_error(conn, :not_found, "not_found")

  defp caller_id(conn), do: Scope.user_id(conn.assigns.current_scope)
end
