defmodule Gamend.Quests.QuestFilter do
  @moduledoc """
  The status filters of a quest list (not stored values).
  """

  @all ~w(in_progress claimable done)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
