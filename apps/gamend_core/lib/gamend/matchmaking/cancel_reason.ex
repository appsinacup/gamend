defmodule Gamend.Matchmaking.CancelReason do
  @moduledoc """
  Why a matchmaking ticket was cancelled, as broadcast to the player.
  """

  @all ~w(left admin offline)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
