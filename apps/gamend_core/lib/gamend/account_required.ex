defmodule Gamend.AccountRequired do
  @moduledoc """
  What a guest may not do until it registers. A guest is an account with no
  email and no sign-in provider, only a device or a browser
  (`Gamend.Accounts.User.anonymous?/1`). The host picks the features:

      config :gamend_core, Gamend.AccountRequired, [:quest_claims, :leaderboards]

  Default: none, so a guest does everything a registered player does.

    * `:quest_claims` — `Gamend.Quests.claim/3` answers
      `{:error, :account_required}` (the API's 403 `account_required`), and
      an `auto_claim` quest does not pay itself. Progress still counts: a
      completed quest waits, and pays once the account is registered.
    * `:leaderboards` — a guest's records are kept but never listed on a
      public board (one not `hidden`): no list, count or rank includes them,
      so a guest moves nobody. Their own record still reads, ranked where it
      would stand, with `hidden: true` (`Gamend.Leaderboards.get_user_record/3`,
      the API's `GET …/me`). Registering lists them at once: it is read from
      the account as it is now, never stored on the record.

  Both apply in core, so every client meets the same rule; a client reads
  the 403 or the `hidden` flag to say why and offer registration.
  """

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User

  @features [:quest_claims, :leaderboards]

  @type feature :: :quest_claims | :leaderboards

  @doc "The features a host can require an account for."
  @spec features() :: [feature()]
  def features, do: @features

  @doc "Whether the host requires an account for `feature`."
  @spec required?(feature()) :: boolean()
  def required?(feature) when feature in @features,
    do: feature in List.wrap(Application.get_env(:gamend_core, __MODULE__, []))

  @doc """
  Whether this user (a `User`, a `Scope` or an id) may use `feature`:
  always when the host does not require an account for it, else only a
  registered account. An unknown id may not.
  """
  @spec allowed?(User.t() | Scope.t() | Ecto.UUID.t() | nil, feature()) :: boolean()
  def allowed?(who, feature) when feature in @features do
    not required?(feature) or registered?(who)
  end

  defp registered?(%User{} = user), do: not User.anonymous?(user)
  defp registered?(%Scope{} = scope), do: registered?(Scope.user(scope))

  defp registered?(user_id) when is_binary(user_id) do
    case Accounts.get_user(user_id) do
      %User{} = user -> registered?(user)
      nil -> false
    end
  end

  defp registered?(_who), do: false
end
