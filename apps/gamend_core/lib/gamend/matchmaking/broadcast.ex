defmodule Gamend.Matchmaking.Broadcast do
  @moduledoc """
  Broadcasts matchmaking events to users: a ticket queued, cancelled, or
  matched into a lobby.

  Core publishes on the `matchmaking:user:<id>` PubSub topic; the user
  channel subscribes on join and forwards to the client (same shape as the
  tournament events). Core never references the web endpoint directly.
  """

  alias Gamend.Matchmaking.Constants

  @doc """
  Tells each ticket's user it is in the queue (`ticket_queued`): `requeued`
  when a failed accept put it back, in its old place. `tickets` carry `id`,
  `user_id`, `match_params` and `queued_at`; the event says `queued_at_ms`.
  """
  @spec ticket_queued([map()], boolean()) :: :ok
  def ticket_queued(tickets, requeued?) do
    Enum.each(tickets, fn ticket ->
      Gamend.Broadcast.publish(
        "matchmaking:user:#{ticket.user_id}",
        {:matchmaking_event, Constants.event_queued(),
         %{
           ticket_id: ticket.id,
           match_params: ticket.match_params,
           queued_at_ms: DateTime.to_unix(ticket.queued_at, :millisecond),
           requeued: requeued?
         }}
      )
    end)
  end

  @doc """
  Tells each ticket's user it left the queue with no match
  (`ticket_cancelled`), and why: `"left"` (they cancelled, or their socket
  closed), `"declined"` or `"timeout"` (an accept), `"offline"` (the sweep),
  `"admin"`, `"unseated"` (the lobby could not seat them). `tickets` carry
  `id` and `user_id`.
  """
  @spec ticket_cancelled([map()], String.t()) :: :ok
  def ticket_cancelled(tickets, reason) do
    Enum.each(tickets, fn ticket ->
      Gamend.Broadcast.publish(
        "matchmaking:user:#{ticket.user_id}",
        {:matchmaking_event, Constants.event_cancelled(), %{ticket_id: ticket.id, reason: reason}}
      )
    end)
  end

  @doc "Notifies every matched user that a lobby has been found."
  @spec match_found([map()], Ecto.UUID.t()) :: :ok
  def match_found(tickets, lobby_id) do
    first = hd(tickets)

    payload = %{
      lobby_id: lobby_id,
      match_params: first.match_params
    }

    Enum.each(tickets, fn ticket ->
      Gamend.Broadcast.publish(
        "matchmaking:user:#{ticket.user_id}",
        {:matchmaking_event, Constants.event_found(), payload}
      )
    end)
  end
end
