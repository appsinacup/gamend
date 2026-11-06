defmodule Gamend.Accounts.GuestMergeRaceTest do
  @moduledoc """
  A guest signing in to their account while still playing as the guest: its
  game client spends, and the account earns quest progress, as the merge
  runs.

  The merge read the guest's balances and granted them to the account,
  leaving the guest holding them, so a spend landing after the read spent
  coins the account had been given too. Its quest step read the periods the
  account had played, then moved the rest in one statement, which failed
  outright when the account played one of them in between. Postgres only
  shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts
  alias Gamend.Accounts.GuestMerge
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Quests
  alias Gamend.Quests.Quest

  @coins 40
  @quests 15

  setup do
    {guest, account} =
      unboxed(fn ->
        {:ok, guest} = Accounts.find_or_create_from_device("race_#{System.unique_integer()}")
        {guest, AccountsFixtures.user_fixture()}
      end)

    ids = [guest.id, account.id]
    cleanup(fn -> Repo.delete_all(from u in User, where: u.id in ^ids) end)

    %{guest: guest, account: account}
  end

  test "coins the guest spends while it merges are not also moved", %{
    guest: guest,
    account: account
  } do
    {:ok, @coins} = unboxed(fn -> Economy.grant(guest.id, "gold", @coins) end)

    # The spends are spread over the merge's few milliseconds.
    spends =
      for i <- 1..@coins do
        fn ->
          Process.sleep(rem(i, 8))
          Economy.spend(guest.id, "gold", 1)
        end
      end

    [merged | spent] = race([fn -> GuestMerge.merge(guest, account) end | spends])

    assert merged == :ok
    refute Enum.any?(spent, &match?({:raised, _}, &1)), inspect(spent)

    paid = Enum.count(spent, &match?({:ok, _}, &1))
    held = unboxed(fn -> Repo.all(gold_balances([guest.id, account.id])) end)

    assert Enum.sum(held) + paid == @coins,
           "#{@coins} coins became #{Enum.sum(held) + paid}: #{inspect(held)} held, #{paid} spent"
  end

  test "quest periods the account plays while it merges stay its own; the rest move", %{
    guest: guest,
    account: account
  } do
    keys = for i <- 1..@quests, do: "merge_race_#{System.unique_integer([:positive])}_#{i}"

    unboxed(fn ->
      for key <- keys do
        {:ok, _} =
          Quests.create_quest(%{
            key: key,
            title: key,
            objectives: [%{event: "merge_race", target: 100, params: %{"quest" => key}}]
          })

        {:ok, _} = Quests.report_event(guest.id, "merge_race", 2, %{"quest" => key})
      end
    end)

    cleanup(fn -> Repo.delete_all(from q in Quest, where: q.key in ^keys) end)

    plays =
      for key <- keys do
        fn -> Quests.report_event(account.id, "merge_race", 1, %{"quest" => key}) end
      end

    [moved | played] = race([fn -> Quests.merge_user_progress(guest.id, account.id) end | plays])

    refute match?({:raised, _}, moved), "the merge raised: #{inspect(moved)}"
    refute Enum.any?(played, &match?({:raised, _}, &1)), inspect(played)

    unboxed(fn ->
      for key <- keys do
        account_row = Quests.get_progress(account.id, key)
        guest_row = Quests.get_progress(guest.id, key)

        # Either the guest's row moved (and the account's play, if it came
        # after, added to it), or the account had played first and the
        # guest's stayed behind. Never neither, never lost.
        case {account_row, guest_row} do
          {%{objective_progress: %{"0" => n}}, nil} -> assert n in [2, 3]
          {%{objective_progress: %{"0" => 1}}, %{objective_progress: %{"0" => 2}}} -> :ok
          other -> flunk("quest #{key}: #{inspect(other)}")
        end
      end
    end)
  end

  defp gold_balances(ids) do
    from w in Gamend.Economy.Wallet,
      where: w.user_id in ^ids and w.currency == "gold",
      select: w.balance
  end
end
