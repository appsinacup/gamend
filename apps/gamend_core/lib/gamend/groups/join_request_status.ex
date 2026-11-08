defmodule Gamend.Groups.JoinRequestStatus do
  @moduledoc """
  The states of a request to join a group.
  """

  @all ~w(pending accepted rejected)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
