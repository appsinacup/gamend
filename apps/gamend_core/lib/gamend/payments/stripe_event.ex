defmodule Gamend.Payments.StripeEvent do
  @moduledoc """
  A Stripe webhook's event name.
  """

  defmacro charge_refunded, do: "charge.refunded"
end
