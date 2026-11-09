defmodule Gamend.Matchmaking.TicketStatus do
  @moduledoc """
  The states of a matchmaking ticket.
  """

  use Gamend.Names, ~w(queued matched cancelled)
end
