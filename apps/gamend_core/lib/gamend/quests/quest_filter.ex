defmodule Gamend.Quests.QuestFilter do
  @moduledoc """
  The status filters of a quest list (not stored values).
  """

  use Gamend.Names, ~w(in_progress claimable done)
end
