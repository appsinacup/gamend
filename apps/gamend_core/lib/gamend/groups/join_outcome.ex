defmodule Gamend.Groups.JoinOutcome do
  @moduledoc """
  What a join request became: `POST /groups/:id/join`.
  """

  use Gamend.Names, ~w(invited request_approved)
end
