defmodule Gamend.ReadyChecks.CheckScope do
  @moduledoc """
  What a ready check runs on.
  """

  @all ~w(lobby party)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
