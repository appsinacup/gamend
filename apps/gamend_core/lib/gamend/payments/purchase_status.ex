defmodule Gamend.Payments.PurchaseStatus do
  @moduledoc """
  The states of a purchase: `purchases.status`.
  """

  @all ~w(pending requires_action completed failed cancelled refunded revoked)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
