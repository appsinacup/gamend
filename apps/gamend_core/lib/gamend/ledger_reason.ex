defmodule Gamend.LedgerReason do
  @moduledoc """
  The ledger reason recorded when a caller gave none.
  """

  @all ~w(unspecified)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
