defmodule Gamend.SortDirection do
  @moduledoc """
  The direction of a sorted list.
  """

  @all ~w(asc desc)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
