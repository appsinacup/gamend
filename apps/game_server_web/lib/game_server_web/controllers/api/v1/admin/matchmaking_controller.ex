defmodule GameServerWeb.Api.V1.Admin.MatchmakingController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Matchmaking
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Admin – Matchmaking"])

  @ticket_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      status: %Schema{type: :string, enum: ["queued", "matched", "cancelled"]},
      match_params: %Schema{type: :object},
      min_players: %Schema{type: :integer},
      max_players: %Schema{type: :integer},
      timeout_ms: %Schema{type: :integer},
      queued_at: %Schema{type: :string, format: "date-time"},
      matched_at: %Schema{type: :string, format: "date-time", nullable: true},
      match_id: %Schema{type: :string, format: :uuid, nullable: true}
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
    operation_id: "admin_list_matchmaking_tickets",
    summary: "List matchmaking tickets (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      status: [
        in: :query,
        schema: %Schema{type: :string, enum: ["queued", "matched", "cancelled"]},
        required: false
      ],
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok:
        {"Tickets", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @ticket_schema},
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
      user_id: params["user_id"],
      page: page,
      page_size: page_size
    ]

    tickets = Matchmaking.list_tickets(filters)
    total = Matchmaking.count_tickets(filters)

    json(conn, %{
      data: Enum.map(tickets, &serialize/1),
      meta: Pagination.meta(page, page_size, length(tickets), total)
    })
  end

  operation(:delete,
    operation_id: "admin_cancel_matchmaking_ticket",
    summary: "Cancel a matchmaking ticket (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok:
        {"Cancelled", "application/json",
         %Schema{type: :object, properties: %{data: @ticket_schema}}},
      not_found: {"Unknown or not queued", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Matchmaking.cancel_ticket(id) do
      {:ok, ticket} ->
        json(conn, %{data: serialize(ticket)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  operation(:stats,
    operation_id: "admin_matchmaking_stats",
    summary: "Matchmaking statistics (admin)",
    security: [%{"authorization" => []}],
    responses: [
      ok:
        {"Stats", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 queued: %Schema{type: :integer},
                 matched: %Schema{type: :integer},
                 cancelled: %Schema{type: :integer},
                 queues: %Schema{type: :array, items: %Schema{type: :object}}
               }
             }
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def stats(conn, _params) do
    json(conn, %{data: Matchmaking.stats()})
  end

  defp serialize(ticket) do
    %{
      id: ticket.id,
      user_id: ticket.user_id,
      status: ticket.status,
      match_params: ticket.match_params,
      min_players: ticket.min_players,
      max_players: ticket.max_players,
      timeout_ms: ticket.timeout_ms,
      queued_at: ticket.queued_at,
      matched_at: ticket.matched_at,
      match_id: ticket.match_id
    }
  end
end
