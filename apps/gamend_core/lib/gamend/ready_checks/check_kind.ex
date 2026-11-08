defmodule Gamend.ReadyChecks.CheckKind do
  @moduledoc """
  Which question a ready check asks.
  """

  @all ~w(ready accept)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
