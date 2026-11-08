defmodule GamendWeb.NavLayout do
  @moduledoc """
  A theme's navigation layout.
  """

  @all ~w(auto sidebar)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
