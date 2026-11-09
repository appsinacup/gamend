defmodule Gamend.OAuth.AuthProvider do
  @moduledoc """
  The OAuth providers a player signs in with.
  """

  use Gamend.Names, ~w(discord apple google facebook github steam)
end
