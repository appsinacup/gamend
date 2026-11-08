defmodule Gamend.Notifications.PreferenceGroup do
  @moduledoc """
  The groups a player's notification choices are made per.
  """

  @all ~w(account social chat quests reports)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
