defmodule Gamend.Chat.FilterSeverity do
  @moduledoc """
  What the word filter does with a match.
  """

  use Gamend.Names, ~w(block mask flag)

  defmacro allow, do: "allow"
end
