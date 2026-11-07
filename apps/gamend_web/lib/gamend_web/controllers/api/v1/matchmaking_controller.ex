defmodule GamendWeb.Api.V1.MatchmakingController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Matchmaking
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    CancelledCountResponse,
    MatchmakingStatsResponse,
    MatchmakingTicketResponse
  }

  alias OpenApiSpex.Schema

  tags(["Matchmaking"])

  operation(:create,
    operation_id: "matchmaking_join",
    summary: "Join the matchmaking queue",
    description: """
    Creates a matchmaking ticket for the caller. Tickets with identical
    match_params are grouped; when enough are queued the server creates a
    hidden lobby and pushes a `match_found` event on the caller's user
    channel; `ticket_queued` and `ticket_cancelled` tell where the ticket
    stands. With `accept_timeout_ms` a formed match asks everyone first (the
    `ready_check_*` events, answered at `POST /me/ready_check`). A lobby's host
    who queues fills that lobby (backfill: the ticket's `lobby_id`). Keep a
    socket connected while queued — a player who stays offline past the grace
    period is dropped from the queue by the sweep.

    A caller in a party queues the whole party: one ticket per member, matched
    as an indivisible unit. Refusals: `already_queued` (409) when the caller or
    any member is already in the queue; `not_party_leader` (403) when a member
    rather than the leader calls this; `party_has_blocked_pair` (403) when two
    members have blocked each other; `party_too_large` (400) when the party
    cannot fit in `max_players`.
    """,
    security: [%{"authorization" => []}],
    request_body:
      {"Ticket", "application/json",
       %Schema{
         type: :object,
         properties: %{
           match_params: %Schema{type: :object},
           min_players: %Schema{type: :integer},
           max_players: %Schema{type: :integer},
           accept_timeout_ms: %Schema{
             type: :integer,
             description:
               "Ask every player to accept a formed match first, within this many ms (a ready check of kind accept); none seats them at once. The game's join hook may set or change it."
           }
         }
       }},
    responses: [
      created: {"Ticket", "application/json", MatchmakingTicketResponse},
      bad_request: Schemas.error("The party cannot fit in max_players"),
      forbidden: Schemas.error("Not the party leader, or two members blocked each other"),
      conflict: Schemas.error("Already queued"),
      unauthorized: Schemas.error("Not authenticated"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def create(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Matchmaking.join(
           user,
           Map.get(params, "match_params", %{}),
           parse_optional_int(params["min_players"]),
           parse_optional_int(params["max_players"]),
           accept_timeout_ms: parse_optional_int(params["accept_timeout_ms"])
         ) do
      {:ok, ticket} ->
        reply_data(conn, :created, serialize(ticket))

      {:error, reason} when is_atom(reason) ->
        reply_error(conn, join_status(reason), reason)

      {:error, changeset} ->
        unprocessable(conn, changeset)
    end
  end

  operation(:delete,
    operation_id: "matchmaking_cancel",
    summary: "Leave the matchmaking queue",
    description: "Cancels all of the caller's queued tickets.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Tickets cancelled", "application/json", CancelledCountResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def delete(conn, _params) do
    cancelled = Matchmaking.cancel(conn.assigns.current_scope.user_id)
    reply_data(conn, %{cancelled: cancelled})
  end

  operation(:me,
    operation_id: "matchmaking_my_ticket",
    summary: "Get my current ticket",
    description: "The caller's queued ticket; 404 `not_queued` when not in the queue.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Ticket", "application/json", MatchmakingTicketResponse},
      not_found: Schemas.error("Not in the queue"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def me(conn, _params) do
    case Matchmaking.current_ticket(conn.assigns.current_scope.user_id) do
      nil -> reply_error(conn, :not_found, "not_queued")
      ticket -> reply_data(conn, serialize(ticket))
    end
  end

  operation(:stats,
    operation_id: "matchmaking_stats",
    summary: "Queue statistics",
    description: "Waiting-player depth per match_params group. Public.",
    responses: [ok: {"Stats", "application/json", MatchmakingStatsResponse}]
  )

  def stats(conn, _params) do
    stats = Matchmaking.stats()
    # Public view: queue depths only, not lifetime matched/cancelled counters.
    reply_data(conn, %{queued: stats.queued, queues: stats.queues})
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp serialize(ticket) do
    %{
      id: ticket.id,
      status: ticket.status,
      match_params: ticket.match_params || %{},
      min_players: ticket.min_players,
      max_players: ticket.max_players,
      timeout_ms: ticket.timeout_ms,
      accept_timeout_ms: ticket.accept_timeout_ms || 0,
      lobby_id: ticket.lobby_id || "",
      queued_at: ticket.queued_at,
      matched_at: ticket.matched_at,
      match_id: ticket.match_id || ""
    }
  end

  # Already in the queue is a state that holds (409); the party rules are
  # refusals (403); a party bigger than the requested match is a request that
  # cannot be met as asked (400).
  defp join_status(:already_queued), do: :conflict
  defp join_status(:party_too_large), do: :bad_request
  defp join_status(_refusal), do: :forbidden

  defp parse_optional_int(value) when is_integer(value), do: value

  defp parse_optional_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_optional_int(_value), do: nil
end
