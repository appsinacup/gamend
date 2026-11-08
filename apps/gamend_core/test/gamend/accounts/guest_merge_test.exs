defmodule Gamend.Accounts.GuestMergeTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.GuestMerge
  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Inventory
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Purchase
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

  describe "entitlements" do
    setup do
      %{now: DateTime.utc_now(:second)}
    end

    test "a granted one reaches the account, with its end and its metadata", %{
      guest: guest,
      account: account,
      now: now
    } do
      ends_at = DateTime.add(now, 7, :day)

      {:ok, _} =
        Payments.grant_entitlement(guest.id, "beta",
          expires_at: ends_at,
          metadata: %{"title" => "Beta"}
        )

      {:ok, _} = Payments.grant_entitlement(guest.id, "lifetime")

      assert :ok = GuestMerge.merge(guest, account)

      beta = entitlement(account, "beta")
      assert beta.status == "active"
      assert beta.expires_at == ends_at
      assert beta.metadata == %{"title" => "Beta"}

      assert entitlement(account, "lifetime").expires_at == nil
      assert Payments.has_entitlement?(account.id, "beta")
      assert Payments.has_entitlement?(account.id, "lifetime")
    end

    test "the account's longer end stands and its metadata is not overwritten", %{
      guest: guest,
      account: account,
      now: now
    } do
      longer = DateTime.add(now, 30, :day)

      {:ok, _} =
        Payments.grant_entitlement(guest.id, "beta",
          expires_at: DateTime.add(now, 7, :day),
          metadata: %{"source" => "guest"}
        )

      {:ok, _} =
        Payments.grant_entitlement(account.id, "beta",
          expires_at: longer,
          metadata: %{"source" => "account"}
        )

      assert :ok = GuestMerge.merge(guest, account)

      beta = entitlement(account, "beta")
      assert beta.expires_at == longer
      assert beta.metadata == %{"source" => "account"}
    end

    test "a longer grant extends the account's end and leaves its metadata", %{
      guest: guest,
      account: account,
      now: now
    } do
      longer = DateTime.add(now, 30, :day)

      {:ok, _} =
        Payments.grant_entitlement(guest.id, "beta",
          expires_at: longer,
          metadata: %{"source" => "guest"}
        )

      {:ok, _} =
        Payments.grant_entitlement(account.id, "beta",
          expires_at: DateTime.add(now, 7, :day),
          metadata: %{"source" => "account"}
        )

      assert :ok = GuestMerge.merge(guest, account)

      beta = entitlement(account, "beta")
      assert beta.expires_at == longer
      assert beta.metadata == %{"source" => "account"}
    end

    test "a row of the account's that has ended comes back with the guest's end", %{
      guest: guest,
      account: account,
      now: now
    } do
      ends_at = DateTime.add(now, 7, :day)
      {:ok, _} = Payments.grant_entitlement(guest.id, "beta", expires_at: ends_at)

      Repo.insert!(%Entitlement{
        user_id: account.id,
        key: "beta",
        status: "active",
        expires_at: DateTime.add(now, -1, :day)
      })

      assert :ok = GuestMerge.merge(guest, account)

      assert entitlement(account, "beta").expires_at == ends_at
      assert Payments.has_entitlement?(account.id, "beta")
    end

    test "one the account had revoked stays revoked", %{guest: guest, account: account} do
      {:ok, _} = Payments.grant_entitlement(guest.id, "beta")
      {:ok, _} = Payments.grant_entitlement(account.id, "beta")
      {:ok, _} = Payments.revoke_entitlement(account.id, "beta")

      assert :ok = GuestMerge.merge(guest, account)

      assert entitlement(account, "beta").status == "revoked"
      refute Payments.has_entitlement?(account.id, "beta")
    end

    test "one a purchase made stays with the guest", %{guest: guest, account: account} do
      purchase =
        Repo.insert!(%Purchase{
          user_id: guest.id,
          provider: "test",
          order_id: "merge_#{System.unique_integer([:positive])}",
          status: "completed"
        })

      Repo.insert!(%Entitlement{
        user_id: guest.id,
        key: "paid",
        status: "active",
        source_purchase_id: purchase.id
      })

      assert :ok = GuestMerge.merge(guest, account)

      refute Payments.entitlement_ever?(account.id, "paid")
    end

    test "one the guest no longer holds is not carried over", %{
      guest: guest,
      account: account,
      now: now
    } do
      {:ok, _} = Payments.grant_entitlement(guest.id, "revoked_one")
      {:ok, _} = Payments.revoke_entitlement(guest.id, "revoked_one")

      Repo.insert!(%Entitlement{
        user_id: guest.id,
        key: "ended_one",
        status: "active",
        expires_at: DateTime.add(now, -1, :day)
      })

      assert :ok = GuestMerge.merge(guest, account)

      refute Payments.entitlement_ever?(account.id, "revoked_one")
      refute Payments.entitlement_ever?(account.id, "ended_one")
    end

    test "a second merge writes nothing and announces nothing", %{
      guest: guest,
      account: account,
      now: now
    } do
      {:ok, _} =
        Payments.grant_entitlement(guest.id, "beta", expires_at: DateTime.add(now, 7, :day))

      {:ok, _} = Payments.grant_entitlement(guest.id, "lifetime")
      Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{account.id}")

      assert :ok = GuestMerge.merge(guest, account)
      assert_receive {:entitlement_changed, %Entitlement{key: "beta"}}
      assert_receive {:entitlement_changed, %Entitlement{key: "lifetime"}}
      beta = entitlement(account, "beta")

      assert :ok = GuestMerge.merge(guest, account)

      refute_receive {:entitlement_changed, _}, 100
      assert entitlement(account, "beta") == beta
    end
  end

  defp entitlement(user, key), do: Repo.get_by!(Entitlement, user_id: user.id, key: key)
end
