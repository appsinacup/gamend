defmodule Gamend.Payments.PaymentEnvironment do
  @moduledoc """
  Where a purchase was made: `purchases.environment`.
  """

  @all ~w(production sandbox test)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
