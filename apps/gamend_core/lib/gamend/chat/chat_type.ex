defmodule Gamend.Chat.ChatType do
  @moduledoc """
  The kinds of conversation.
  """

  @all ~w(lobby group friend party)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
