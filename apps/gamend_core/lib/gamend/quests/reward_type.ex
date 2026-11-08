defmodule Gamend.Quests.RewardType do
  @moduledoc """
  What a quest's reward grants.
  """

  @all ~w(currency item)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
