defmodule Gamend.Accounts.ThemeName do
  @moduledoc """
  A user's theme preference.
  """

  @all ~w(dark light system)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
