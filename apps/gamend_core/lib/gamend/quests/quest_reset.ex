defmodule Gamend.Quests.QuestReset do
  @moduledoc """
  How often a quest resets.
  """

  use Gamend.Names, ~w(never daily weekly monthly repeat interval)
end
