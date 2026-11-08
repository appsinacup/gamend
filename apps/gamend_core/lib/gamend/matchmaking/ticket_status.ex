defmodule Gamend.Matchmaking.TicketStatus do
  @moduledoc """
  The states of a matchmaking ticket.
  """

  @all ~w(queued matched cancelled)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
