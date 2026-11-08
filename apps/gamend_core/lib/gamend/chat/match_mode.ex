defmodule Gamend.Chat.MatchMode do
  @moduledoc """
  How the word filter matches a word.
  """

  @all ~w(substring exact)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
