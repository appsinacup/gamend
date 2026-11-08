defmodule Gamend.Quests.QuestReset do
  @moduledoc """
  How often a quest resets.
  """

  @all ~w(never daily weekly monthly repeat interval)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
