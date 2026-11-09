defmodule Gamend.Payments.StripeSetupStep do
  @moduledoc """
  The steps of `mix gamend.stripe.setup`.
  """

  use Gamend.Names, ~w(webhook product portal)
end
