defmodule Gamend.LocalHost do
  @moduledoc """
  The name a server uses for itself when no host is set.
  """

  @all ~w(localhost)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
