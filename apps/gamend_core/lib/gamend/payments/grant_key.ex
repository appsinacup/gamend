defmodule Gamend.Payments.GrantKey do
  @moduledoc """
  Keys of a product's grant config that core and the store read.
  """

  @all ~w(download)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
