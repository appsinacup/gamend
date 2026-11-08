defmodule Gamend.ParamType do
  @moduledoc """
  The type names shown for an argument in the runtime pages.
  """

  @all ~w(string integer float boolean list map unknown)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
