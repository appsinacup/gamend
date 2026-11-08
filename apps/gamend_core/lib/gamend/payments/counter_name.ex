defmodule Gamend.Payments.CounterName do
  @moduledoc """
  The counters of payments in `Gamend.Payments.Counters`.
  """

  @all ~w(webhook)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  defmacro checkout_opened, do: "checkout.opened"
end
