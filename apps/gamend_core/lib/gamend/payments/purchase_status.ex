defmodule Gamend.Payments.PurchaseStatus do
  @moduledoc """
  The states of a purchase: `purchases.status`.
  """

  use Gamend.Names, ~w(pending requires_action completed failed cancelled refunded revoked)
end
