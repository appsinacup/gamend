defmodule Gamend.Matchmaking.Broadcast do
  @moduledoc """
  Broadcasts matchmaking events to users.

  Core publishes on the `matchmaking:user:<id>` PubSub topic; the user
  channel subscribes on join and forwards to the client (same shape as the
  tournament events). Core never references the web endpoint directly.
  """

  alias Gamend.Matchmaking.Constants

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
