defmodule Gamend.Tournaments.DeadlinePolicy do
  @moduledoc """
  What happens to a match past its deadline.
  """

  use Gamend.Names, ~w(forfeit_both)
end
