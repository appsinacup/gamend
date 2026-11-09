defmodule GamendWeb.ChannelTopic do
  @moduledoc """
  The kinds of channel, as a topic's first word.
  """

  use Gamend.Names, ~w(user lobby lobbies group groups party)
end
