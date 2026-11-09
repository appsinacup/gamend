defmodule Gamend.Quests.QuestStatus do
  @moduledoc """
  A player's progress on a quest: `quest_progress.status`.
  """

  use Gamend.Names, ~w(active completed claimed)
end
