defmodule Gamend.Leaderboards.ScoreOperator do
  @moduledoc """
  How a leaderboard's records combine a new score.
  """

  use Gamend.Names, ~w(set best incr decr)
end
