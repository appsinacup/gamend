defmodule Gamend.Lobbies.LobbyState do
  @moduledoc """
  A lobby's initial state.
  """

  @all ~w(created)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
