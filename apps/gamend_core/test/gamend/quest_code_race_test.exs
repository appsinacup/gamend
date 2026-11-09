defmodule Gamend.QuestCodeRaceTest do
  @moduledoc """
  Redemptions landing together. One per player is the unique index on
  `quest_progress`, capacity the conditional update on `quest_codes`, and
  every check before them only refuses early, so these hold on a read taken
  before any of the others wrote. Postgres only shows it; see
  `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Quests
  alias Gamend.Quests.Codes
  alias Gamend.Quests.Quest

  @racers 12

  setup do
    quest =
      unboxed(fn ->
        {:ok, quest} =
          Quests.create_quest(%{
            key: "race_code_#{System.unique_integer([:positive])}",
            title: "Race",
            code_only: true,
            rewards: [%{type: "currency", code: "gold", amount: 10}]
          })

        quest
      end)

    cleanup(fn -> Repo.delete_all(from q in Quest, where: q.key == ^quest.key) end)

    %{quest: quest}
  end

  defp users(count) do
    users = unboxed(fn -> for _ <- 1..count, do: AccountsFixtures.user_fixture() end)
    ids = Enum.map(users, & &1.id)
    cleanup(fn -> Repo.delete_all(from u in User, where: u.id in ^ids) end)
    users
  end

  defp code(quest, attrs) do
    unboxed(fn ->
      {:ok, code} = Quests.create_code(quest, attrs)
      code
    end)
  end

  defp gold(user), do: unboxed(fn -> Economy.balance(user.id, "gold") end)

  defp refute_raised(results),
    do: refute(Enum.any?(results, &match?({:raised, _}, &1)), inspect(results))

  test "players racing a code capped at K: exactly K complete", %{quest: quest} do
    code = code(quest, %{token: "CAPPED", max_uses: 3})
    users = users(@racers)

    results =
      race(Enum.map(users, fn user -> fn -> Quests.redeem_code(user.id, "CAPPED") end end))

    refute_raised(results)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 3
    assert Enum.count(results, &(&1 == {:error, :code_not_found})) == @racers - 3

    assert unboxed(fn -> Codes.get(code.id) end).uses == 3
    assert users |> Enum.map(&gold/1) |> Enum.sum() == 30
  end

  test "one player racing one code is paid once", %{quest: quest} do
    code = code(quest, %{token: "ONCE", max_uses: nil})
    [user] = users(1)

    results = race(@racers, fn _ -> Quests.redeem_code(user.id, "ONCE") end)

    refute_raised(results)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_redeemed})) == @racers - 1

    assert gold(user) == 10
    assert unboxed(fn -> Codes.get(code.id) end).uses == 1
  end

  test "one player racing two codes of one quest is paid once and spends one use", %{quest: quest} do
    first = code(quest, %{token: "FIRST"})
    second = code(quest, %{token: "SECOND"})
    [user] = users(1)

    results =
      race([
        fn -> Quests.redeem_code(user.id, "FIRST") end,
        fn -> Quests.redeem_code(user.id, "SECOND") end
      ])

    refute_raised(results)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_redeemed})) == 1

    assert gold(user) == 10

    uses = unboxed(fn -> Codes.get(first.id).uses + Codes.get(second.id).uses end)
    assert uses == 1
  end
end
