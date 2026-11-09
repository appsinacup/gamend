defmodule Gamend.Quests.QuestCodeStatus do
  @moduledoc """
  Whether a redemption code still works: `quest_codes.status`.
  """

  use Gamend.Names, ~w(active revoked)
end
