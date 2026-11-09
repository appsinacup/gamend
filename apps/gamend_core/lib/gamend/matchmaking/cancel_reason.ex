defmodule Gamend.Matchmaking.CancelReason do
  @moduledoc """
  Why a matchmaking ticket was cancelled, as broadcast to the player.
  """

  use Gamend.Names, ~w(left admin offline)
end
