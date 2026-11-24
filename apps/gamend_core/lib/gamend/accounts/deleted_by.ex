defmodule Gamend.Accounts.DeletedBy do
  @moduledoc """
  Who or what deleted an account, the `by` of the `accounts.deleted` event
  `Gamend.Accounts.delete_user/2` counts:

    * `self` — the player, from their settings or the API (`request_deletion/2`,
      at once or when the grace days run out);
    * `admin` — an admin, from the admin pages or the admin API;
    * `guest_merge` — a guest signed in to an account and was merged into it;
    * `orphan` — a provider-only account its identity's owner removed while
      linking that provider to the account they were signed in to;
    * `anonymous`, `unconfirmed`, `inactive` — a `Gamend.Retention` sweep.
  """

  use Gamend.Names, ~w(self admin guest_merge orphan anonymous unconfirmed inactive)
end
