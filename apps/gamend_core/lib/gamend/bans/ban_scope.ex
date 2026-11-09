defmodule Gamend.Bans.BanScope do
  @moduledoc """
  Where a chat ban applies.
  """

  use Gamend.Names, ~w(global lobby group party)
end
