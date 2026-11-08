defmodule Gamend.Payments.PurchaseMetadata do
  @moduledoc """
  Keys payments keeps in a purchase's metadata.
  """

  @all ~w(stripe_subscription_id paid_through)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
