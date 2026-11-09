defmodule Gamend.Parties.PartyInviteStatus do
  @moduledoc """
  The states of an invitation to a party.
  """

  use Gamend.Names, ~w(pending accepted declined cancelled)
end
