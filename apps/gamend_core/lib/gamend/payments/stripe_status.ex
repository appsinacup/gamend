defmodule Gamend.Payments.StripeStatus do
  @moduledoc """
  Stripe's own statuses, read off its objects (not the rows it updates).
  """

  use Gamend.Names, ~w(active trialing canceled incomplete_expired paid open expired completed)
end
