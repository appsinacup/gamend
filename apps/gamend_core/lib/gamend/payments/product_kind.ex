defmodule Gamend.Payments.ProductKind do
  @moduledoc """
  What a product grants.
  """

  use Gamend.Names, ~w(entitlement consumable subscription)

  defmacro granted, do: "granted"
end
