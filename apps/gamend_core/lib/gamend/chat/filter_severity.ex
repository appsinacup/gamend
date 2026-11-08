defmodule Gamend.Chat.FilterSeverity do
  @moduledoc """
  What the word filter does with a match.
  """

  @all ~w(block mask flag)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  defmacro allow, do: "allow"

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
