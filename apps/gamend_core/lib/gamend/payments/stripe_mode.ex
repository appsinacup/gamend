defmodule Gamend.Payments.StripeMode do
  @moduledoc """
  A Stripe Checkout session's `mode`.
  """

  @all ~w(payment subscription)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
