defmodule Gamend.Payments.ProductKind do
  @moduledoc """
  What a product grants.
  """

  @all ~w(entitlement consumable subscription)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  defmacro granted, do: "granted"

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
