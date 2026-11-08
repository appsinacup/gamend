defmodule Gamend.Quests.PeriodKey do
  @moduledoc """
  The period key of a quest that never resets.
  """

  @all ~w(static)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
