defmodule Gamend.Payments.PurchaseMetadata do
  @moduledoc """
  Keys payments keeps in a purchase's metadata.
  """

  use Gamend.Names, ~w(stripe_subscription_id paid_through checkout_decline)
end
