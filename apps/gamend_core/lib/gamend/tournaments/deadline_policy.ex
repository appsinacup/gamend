defmodule Gamend.Tournaments.DeadlinePolicy do
  @moduledoc """
  What happens to a match past its deadline.
  """

  @all ~w(forfeit_both)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
