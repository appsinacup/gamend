defmodule Gamend.Payments.ChargeKind do
  @moduledoc """
  What a `payment_charges` row records: the `sale` that started a purchase,
  a subscription's `renewal`, or the `refund` (or lost dispute) that gave the
  money back.
  """

  use Gamend.Names, ~w(sale renewal refund)
end
