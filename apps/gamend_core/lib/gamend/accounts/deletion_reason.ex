defmodule Gamend.Accounts.DeletionReason do
  @moduledoc """
  Why a player deleted their own account: the optional answer on the
  account settings page, counted by `Gamend.Accounts.request_deletion/2` as
  the `reason` of `accounts.deletion_requested`. A fixed list, never free
  text, so nothing the player typed outlives the account.

  One reason per kind of cause, the set most account-deletion surveys share:
  stopped using it, not a fit, switched away, it broke, privacy, other.
  """

  use Gamend.Names, ~w(not_using not_for_me other_app problems privacy other)
end
