defmodule GamendWeb.ColorScheme do
  @moduledoc """
  A page's colour scheme.
  """

  @all ~w(light dark)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
