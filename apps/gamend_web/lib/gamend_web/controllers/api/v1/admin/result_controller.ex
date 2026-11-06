defmodule GamendWeb.Api.V1.Admin.ResultController do
  @moduledoc """
  Admin API for results (`Gamend.Results`): every play, whatever its
  visibility, the same list and actions `/admin/results` has, so a script
  can do what the console can.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Results
  alias Gamend.Results.Result
  alias GamendWeb.ResultReads
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{OkResponse, ResultEventsResponse, ResultPage, ResultResponse}
  alias OpenApiSpex.Schema

  tags(["Admin – Results"])

  operation(:index,
    operation_id: "admin_list_results",
    summary: "List results (admin)",
    description: "Every play, newest first, each with its stats by event key.",
    security: [%{"authorization" => []}],
    parameters: [
      kind: [in: :query, schema: %Schema{type: :string}],
      status: [in: :query, schema: %Schema{type: :string, enum: ~w(open ended)}],
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      lobby_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok: {"Results", "application/json", ResultPage}
    ]
  )

  def index(conn, params) do
    filters = Map.take(params, ~w(kind status user_id lobby_id))
    {page, page_size} = GamendWeb.Pagination.params(params)
    results = Results.list(filters, page: page, page_size: page_size)
    stats = results |> Enum.map(& &1.id) |> Results.stats()
    rows = Enum.map(results, &ResultReads.serialize(&1, Map.get(stats, &1.id, %{})))
    reply_page(conn, rows, page, page_size, Results.count(filters))
  end

  operation(:show,
    operation_id: "admin_get_result",
    summary: "Get a result (admin)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [
      ok: {"The result", "application/json", ResultResponse},
      not_found: Schemas.error("Not found")
    ]
  )

  def show(conn, %{"id" => id}) do
    case find(id) do
      %Result{} = result -> reply_data(conn, ResultReads.serialize(result, Results.stats(result)))
      nil -> reply_error(conn, :not_found, "not_found")
    end
  end

  operation(:events,
    operation_id: "admin_list_result_events",
    summary: "List a result's events (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      after: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      limit: [in: :query, schema: %Schema{type: :integer, default: 500}]
    ],
    responses: [
      ok: {"The events", "application/json", ResultEventsResponse},
      not_found: Schemas.error("Not found")
    ]
  )

  def events(conn, %{"id" => id} = params) do
    case find(id) do
      %Result{} = result ->
        limit = with l when is_binary(l) <- params["limit"], {n, ""} <- Integer.parse(l), do: n
        after_id = Gamend.UUIDv7.cast_or_nil(params["after"])
        events = Results.events(result.id, after: after_id, limit: limit)
        reply_data(conn, %{result_id: result.id, events: events})

      nil ->
        reply_error(conn, :not_found, "not_found")
    end
  end

  operation(:delete,
    operation_id: "admin_delete_result",
    summary: "Delete a result and its events (admin)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      not_found: Schemas.error("Not found")
    ]
  )

  def delete(conn, %{"id" => id}) do
    with %Result{} = result <- find(id),
         {:ok, _deleted} <- Results.delete(result) do
      reply_ok(conn)
    else
      nil -> reply_error(conn, :not_found, "not_found")
      # `not_found` when a delete racing this one took it first.
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  defp find(id), do: Gamend.UUIDv7.cast_or_nil(id) && Results.get(id)
end
