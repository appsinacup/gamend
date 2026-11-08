defmodule Gamend.Quests.QuestCategory do
  @moduledoc """
  A quest category with a meaning of its own.
  """

  @all ~w(achievement)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
