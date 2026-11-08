defmodule GamendWeb.Api.V1.Admin.MatchmakingController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Matchmaking
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    AdminMatchmakingStatsResponse,
    AdminMatchmakingTicketPage,
    AdminMatchmakingTicketResponse
  }

  alias OpenApiSpex.Schema

  tags(["Admin – Matchmaking"])

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
      ok: {"Tickets", "application/json", AdminMatchmakingTicketPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def index(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)

    filters = [
      status: params["status"],
      user_id: params["user_id"],
      page: page,
      page_size: page_size
    ]

    tickets = Matchmaking.list_tickets(filters)
    total = Matchmaking.count_tickets(filters)

    reply_page(conn, Enum.map(tickets, &serialize/1), page, page_size, total)
  end

  operation(:delete,
    operation_id: "admin_cancel_matchmaking_ticket",
    summary: "Cancel a matchmaking ticket (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Cancelled", "application/json", AdminMatchmakingTicketResponse},
      not_found: Schemas.error("Unknown or not queued"),
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Matchmaking.cancel_ticket(id) do
      {:ok, ticket} ->
        reply_data(conn, serialize(ticket))

      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")
    end
  end

  operation(:stats,
    operation_id: "admin_matchmaking_stats",
    summary: "Matchmaking statistics (admin)",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Stats", "application/json", AdminMatchmakingStatsResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def stats(conn, _params) do
    reply_data(conn, Matchmaking.stats())
  end

  defp serialize(ticket) do
    %{
      id: ticket.id,
      user_id: ticket.user_id,
      status: ticket.status,
      match_params: ticket.match_params || %{},
      min_players: ticket.min_players,
      max_players: ticket.max_players,
      timeout_ms: ticket.timeout_ms,
      lobby_id: ticket.lobby_id || "",
      queued_at: ticket.queued_at,
      matched_at: ticket.matched_at,
      match_id: ticket.match_id || ""
    }
  end
end
