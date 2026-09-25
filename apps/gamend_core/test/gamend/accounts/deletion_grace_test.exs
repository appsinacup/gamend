defmodule Gamend.Accounts.DeletionGraceTest do
  # Settings are global Application config.
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.SettingsHelpers

  setup do
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Accounts, :deletion_grace_days) end)
    %{user: AccountsFixtures.user_fixture()}
  end

  test "with no grace period the account is deleted at once", %{user: user} do
    assert {:ok, :deleted} = Accounts.request_deletion(user)
    refute Repo.get(User, user.id)
  end

  test "with a grace period the account is scheduled and signed out everywhere",
       %{user: user} do
    SettingsHelpers.put(:gamend_core, Accounts, :deletion_grace_days, 30)
    token = Accounts.generate_user_session_token(user)

    assert {:ok, {:scheduled, scheduled, [_ | _]}} = Accounts.request_deletion(user)
    assert DateTime.diff(scheduled.deletion_scheduled_at, DateTime.utc_now(), :day) in 29..30
    assert scheduled.token_version > user.token_version
    assert Accounts.deletion_scheduled?(scheduled)
    refute Accounts.get_user_by_session_token(token)

    # Asking again keeps the first date.
    assert {:ok, {:scheduled, again, _}} = Accounts.request_deletion(scheduled)
    assert again.deletion_scheduled_at == scheduled.deletion_scheduled_at
  end

  test "cancelling keeps the account", %{user: user} do
    SettingsHelpers.put(:gamend_core, Accounts, :deletion_grace_days, 30)
    {:ok, {:scheduled, scheduled, _}} = Accounts.request_deletion(user)

    assert {:ok, kept} = Accounts.cancel_deletion(scheduled)
    refute Accounts.deletion_scheduled?(kept)
    refute Accounts.deletion_scheduled?(Accounts.get_user!(user.id))
  end

  test "retention deletes an account once its date has passed, and not before",
       %{user: user} do
    SettingsHelpers.put(:gamend_core, Accounts, :deletion_grace_days, 30)
    {:ok, {:scheduled, _, _}} = Accounts.request_deletion(user)

    assert %{scheduled_deletions: 0} = Gamend.Retention.prune_all()
    assert Repo.get(User, user.id)

    past = DateTime.add(DateTime.utc_now(:second), -1, :minute)
    Repo.update_all(User, set: [deletion_scheduled_at: past])

    assert %{scheduled_deletions: 1} = Gamend.Retention.prune_all()
    refute Repo.get(User, user.id)
  end
end
