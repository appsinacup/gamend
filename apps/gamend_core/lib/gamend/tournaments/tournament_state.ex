defmodule Gamend.Tournaments.TournamentState do
  @moduledoc """
  The states of a tournament.
  """

  @all ~w(scheduled registration running finished cancelled)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
