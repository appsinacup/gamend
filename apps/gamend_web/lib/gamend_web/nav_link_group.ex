defmodule GamendWeb.NavLinkGroup do
  @moduledoc """
  The theme's lists of navigation links.
  """

  @all ~w(primary_links guest_links authenticated_links account_links)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
