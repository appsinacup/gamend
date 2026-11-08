defmodule Gamend.Tournaments.EntryState do
  @moduledoc """
  A participant's state in a tournament.
  """

  @all ~w(registered active eliminated winner)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
