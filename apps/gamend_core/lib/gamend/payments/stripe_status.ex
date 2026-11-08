defmodule Gamend.Payments.StripeStatus do
  @moduledoc """
  Stripe's own statuses, read off its objects (not the rows it updates).
  """

  @all ~w(active trialing canceled incomplete_expired paid open expired completed)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
