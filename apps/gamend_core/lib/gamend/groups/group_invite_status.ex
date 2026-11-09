defmodule Gamend.Groups.GroupInviteStatus do
  @moduledoc """
  The states of an invitation to a group.
  """

  use Gamend.Names, ~w(pending accepted declined cancelled)
end
