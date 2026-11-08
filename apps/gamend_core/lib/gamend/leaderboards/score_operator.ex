defmodule Gamend.Leaderboards.ScoreOperator do
  @moduledoc """
  How a leaderboard's records combine a new score.
  """

  @all ~w(set best incr decr)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
