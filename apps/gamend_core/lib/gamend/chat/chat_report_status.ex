defmodule Gamend.Chat.ChatReportStatus do
  @moduledoc """
  The states of a report about a chat message.
  """

  use Gamend.Names, ~w(open reviewing actioned dismissed)
end
