defmodule Gamend.Friends.FriendshipStatus do
  @moduledoc """
  The states of a friendship row.
  """

  use Gamend.Names, ~w(pending accepted rejected blocked)
end
