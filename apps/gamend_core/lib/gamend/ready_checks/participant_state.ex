defmodule Gamend.ReadyChecks.ParticipantState do
  @moduledoc """
  A participant's answer to a ready check.
  """

  use Gamend.Names, ~w(pending ready declined timed_out)
end
