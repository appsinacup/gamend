defmodule Gamend.Groups.JoinRequestStatus do
  @moduledoc """
  The states of a request to join a group.
  """

  use Gamend.Names, ~w(pending accepted rejected)
end
