defmodule Gamend.Analytics.SegmentName do
  @moduledoc """
  The analytics segments that are not everyone.
  """

  @all ~w(registered guest)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  defmacro all_users, do: "all"
end
