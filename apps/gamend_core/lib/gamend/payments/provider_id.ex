defmodule Gamend.Payments.ProviderId do
  @moduledoc """
  The payment providers core knows, as stored in `purchases.provider`.
  """

  @all ~w(stripe apple google steam)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
