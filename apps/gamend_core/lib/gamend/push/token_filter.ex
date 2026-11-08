defmodule Gamend.Push.TokenFilter do
  @moduledoc """
  The status filters of the push tokens list.
  """

  @all ~w(live disabled)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
