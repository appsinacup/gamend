defmodule Gamend.Payments.StripeKeyMode do
  @moduledoc """
  What a Stripe API key is for, read from its prefix.
  """

  @all ~w(test live unknown)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
