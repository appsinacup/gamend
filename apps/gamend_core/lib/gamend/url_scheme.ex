defmodule Gamend.UrlScheme do
  @moduledoc """
  URL schemes.
  """

  @all ~w(http https)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
