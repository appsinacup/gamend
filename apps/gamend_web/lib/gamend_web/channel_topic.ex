defmodule GamendWeb.ChannelTopic do
  @moduledoc """
  The kinds of channel, as a topic's first word.
  """

  @all ~w(user lobby lobbies group groups party)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
