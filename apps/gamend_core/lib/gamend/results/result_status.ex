defmodule Gamend.Results.ResultStatus do
  @moduledoc """
  The states of a play's result.
  """

  @all ~w(open ended)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
