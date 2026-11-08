defmodule GamendWeb.FormName do
  @moduledoc """
  The names a form's params arrive under, as `as:` of `to_form/2`.
  """

  @all ~w(user group lobby party quest leaderboard grant record)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
