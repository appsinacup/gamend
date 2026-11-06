defmodule Gamend.Accounts.GuestMergeTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.GuestMerge
  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Inventory
  alias Gamend.Quests

  setup do
    {:ok, guest} = Accounts.find_or_create_from_device("merge_#{System.unique_integer()}")
    %{guest: guest, account: AccountsFixtures.user_fixture()}
  end

  test "the wallet and inventory move: the guest keeps nothing it could still spend", %{
    guest: guest,
    account: account
  } do
    {:ok, 100} = Economy.grant(guest.id, "gold", 100)
    {:ok, 5} = Economy.grant(account.id, "gold", 5)
    {:ok, 3} = Inventory.grant_item(guest.id, "potion", 3)

    assert :ok = GuestMerge.merge(guest, account)

    assert Economy.balance(account.id, "gold") == 105
    assert Inventory.quantity(account.id, "potion") == 3

    # It was copied: the guest, deleted only later, still held all of it, and
    # its token or socket could spend it a second time.
    assert Economy.balance(guest.id, "gold") == 0
    assert Inventory.quantity(guest.id, "potion") == 0
    assert {:error, :insufficient_funds} = Economy.spend(guest.id, "gold", 1)

    # A retried sign-in moves nothing twice.
    assert :ok = GuestMerge.merge(guest, account)
    assert Economy.balance(account.id, "gold") == 105
  end

  test "the guest's tokens stop working before anything moves", %{
    guest: guest,
    account: account
  } do
    token = Accounts.generate_user_session_token(guest)
    version = Repo.get!(Accounts.User, guest.id).token_version

    assert :ok = GuestMerge.merge(guest, account)

    assert Accounts.get_user_by_session_token(token) == nil
    assert Repo.get!(Accounts.User, guest.id).token_version == version + 1
  end

  test "quest progress moves row by row, and a period the account has stays its own", %{
    guest: guest,
    account: account
  } do
    for key <- ~w(merge_a merge_b) do
      {:ok, _} =
        Quests.create_quest(%{
          key: key,
          title: key,
          objectives: [%{event: "merge_win", target: 10, params: %{"quest" => key}}]
        })
    end

    {:ok, _} = Quests.report_event(guest.id, "merge_win", 2, %{"quest" => "merge_a"})
    {:ok, _} = Quests.report_event(guest.id, "merge_win", 2, %{"quest" => "merge_b"})
    {:ok, _} = Quests.report_event(account.id, "merge_win", 1, %{"quest" => "merge_a"})

    assert Quests.merge_user_progress(guest.id, account.id) == 1

    assert Quests.get_progress(account.id, "merge_a").objective_progress == %{"0" => 1}
    assert Quests.get_progress(account.id, "merge_b").objective_progress == %{"0" => 2}
    assert Quests.get_progress(guest.id, "merge_a").objective_progress == %{"0" => 2}
  end
end
