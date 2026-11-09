defmodule Gamend.Payments.PaymentEnvironment do
  @moduledoc """
  Where a purchase was made: `purchases.environment`.
  """

  use Gamend.Names, ~w(production sandbox test)
end
