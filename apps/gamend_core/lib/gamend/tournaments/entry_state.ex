defmodule Gamend.Tournaments.EntryState do
  @moduledoc """
  A participant's state in a tournament.
  """

  use Gamend.Names, ~w(registered active eliminated winner)
end
