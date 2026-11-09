defmodule Gamend.Payments.CounterName do
  @moduledoc """
  The counters of payments in `Gamend.Payments.Counters`.
  """

  use Gamend.Names, ~w(webhook)

  defmacro checkout_opened, do: "checkout.opened"
end
