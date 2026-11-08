defmodule Gamend.Chat.ChatReportStatus do
  @moduledoc """
  The states of a report about a chat message.
  """

  @all ~w(open reviewing actioned dismissed)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
