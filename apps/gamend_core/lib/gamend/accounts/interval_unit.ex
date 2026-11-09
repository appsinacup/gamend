defmodule Gamend.Accounts.IntervalUnit do
  @moduledoc """
  The unit of the age limits on account tokens, as SQL's `ago/2` reads it.
  """

  use Gamend.Names, ~w(day)
end
