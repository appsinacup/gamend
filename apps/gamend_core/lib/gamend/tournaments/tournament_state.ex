defmodule Gamend.Tournaments.TournamentState do
  @moduledoc """
  The states of a tournament.
  """

  use Gamend.Names, ~w(scheduled registration running finished cancelled)
end
