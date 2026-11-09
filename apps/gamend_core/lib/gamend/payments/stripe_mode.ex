defmodule Gamend.Payments.StripeMode do
  @moduledoc """
  A Stripe Checkout session's `mode`.
  """

  use Gamend.Names, ~w(payment subscription)
end
