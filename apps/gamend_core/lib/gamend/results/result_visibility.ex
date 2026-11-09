defmodule Gamend.Results.ResultVisibility do
  @moduledoc """
  Who can read a play's result.
  """

  use Gamend.Names, ~w(server_only public owner_only lobby_members_only owner_or_lobby_member)
end
