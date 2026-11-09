defmodule GamendWeb.FormName do
  @moduledoc """
  The names a form's params arrive under, as `as:` of `to_form/2`.
  """

  use Gamend.Names, ~w(user group lobby party quest leaderboard grant record)
end
