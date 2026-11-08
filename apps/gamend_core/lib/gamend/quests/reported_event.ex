defmodule Gamend.Quests.ReportedEvent do
  @moduledoc """
  An event core reports to the quests of a player.
  """

  @all ~w(login)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
