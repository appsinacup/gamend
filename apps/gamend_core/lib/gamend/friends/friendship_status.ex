defmodule Gamend.Friends.FriendshipStatus do
  @moduledoc """
  The states of a friendship row.
  """

  @all ~w(pending accepted rejected blocked)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
