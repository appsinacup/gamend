defmodule Gamend.Payments.StripeSetupStep do
  @moduledoc """
  The steps of `mix gamend.stripe.setup`.
  """

  @all ~w(webhook product portal)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
