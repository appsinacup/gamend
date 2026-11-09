defmodule Gamend.Analytics.SegmentName do
  @moduledoc """
  The analytics segments that are not everyone.
  """

  use Gamend.Names, ~w(registered guest)

  defmacro all_users, do: "all"
end
