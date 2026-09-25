defmodule Gamend.Accounts.LoginLockoutsTest do
  # Settings are global Application config.
  use Gamend.DataCase, async: false

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.LoginLockout
  alias Gamend.AccountsFixtures
  alias Gamend.SettingsHelpers

  @password AccountsFixtures.valid_user_password()

  setup do
    SettingsHelpers.put(:gamend_core, Accounts, :lockout_attempts, 3)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Accounts, :lockout_attempts) end)

    user = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    %{user: user}
  end

  defp fail(email), do: Accounts.authenticate_by_password(email, "wrong password!")

  test "the failure that reaches the limit locks, and a right password is refused then",
       %{user: user} do
    assert {:error, :invalid_credentials} = fail(user.email)
    assert {:error, :invalid_credentials} = fail(user.email)
    assert {:error, {:locked, seconds}} = fail(user.email)
    assert seconds in 1..(15 * 60)

    assert {:error, {:locked, _}} = Accounts.authenticate_by_password(user.email, @password)
    assert Accounts.get_user_by_email_and_password(user.email, @password) == nil
  end

  test "an address with no account locks the same way" do
    email = AccountsFixtures.unique_user_email()

    assert {:error, :invalid_credentials} = fail(email)
    assert {:error, :invalid_credentials} = fail(email)
    assert {:error, {:locked, _}} = fail(email)
  end

  test "the address is matched however it is typed", %{user: user} do
    fail(user.email)
    fail(" " <> String.upcase(user.email))
    assert {:error, {:locked, _}} = fail(user.email)
  end

  test "a right password clears the count", %{user: user} do
    fail(user.email)
    fail(user.email)
    assert {:ok, _} = Accounts.authenticate_by_password(user.email, @password)
    assert Repo.aggregate(LoginLockout, :count) == 0

    assert {:error, :invalid_credentials} = fail(user.email)
    assert {:error, :invalid_credentials} = fail(user.email)
  end

  test "failures outside the window start a new count", %{user: user} do
    fail(user.email)
    fail(user.email)

    old = DateTime.add(DateTime.utc_now(:second), -16, :minute)
    Repo.update_all(LoginLockout, set: [window_started_at: old])

    assert {:error, :invalid_credentials} = fail(user.email)
    assert Repo.one(from(l in LoginLockout, select: l.failures)) == 1
  end

  test "a lock runs out, and the address gets every attempt back", %{user: user} do
    fail(user.email)
    fail(user.email)
    assert {:error, {:locked, _}} = fail(user.email)

    past = DateTime.add(DateTime.utc_now(:second), -1, :second)
    Repo.update_all(LoginLockout, set: [unlocks_at: past])

    assert {:ok, _} = Accounts.authenticate_by_password(user.email, @password)
  end

  test "0 attempts turns the lockout off", %{user: user} do
    SettingsHelpers.put(:gamend_core, Accounts, :lockout_attempts, 0)

    for _ <- 1..5, do: assert({:error, :invalid_credentials} = fail(user.email))
    assert {:ok, _} = Accounts.authenticate_by_password(user.email, @password)
    assert Repo.aggregate(LoginLockout, :count) == 0
  end

  test "retention prunes rows whose window and lock have run out", %{user: user} do
    fail(user.email)
    Gamend.Retention.prune_all()
    assert Repo.aggregate(LoginLockout, :count) == 1

    old = DateTime.add(DateTime.utc_now(:second), -20, :minute)
    Repo.update_all(LoginLockout, set: [updated_at: old])
    assert %{login_lockouts: 1} = Gamend.Retention.prune_all()
    assert Repo.aggregate(LoginLockout, :count) == 0
  end
end
