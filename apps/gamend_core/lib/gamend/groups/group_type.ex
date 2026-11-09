defmodule Gamend.Groups.GroupType do
  @moduledoc """
  Who can find and join a group: `groups.type`.
  """

  use Gamend.Names, ~w(public private hidden)
end
