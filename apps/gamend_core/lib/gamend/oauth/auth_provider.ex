defmodule Gamend.OAuth.AuthProvider do
  @moduledoc """
  The OAuth providers a player signs in with.
  """

  @all ~w(discord apple google facebook github steam)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
