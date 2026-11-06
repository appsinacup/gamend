defmodule Gamend.QuestClaimRaceTest do
  @moduledoc """
  Two claims of one `repeat` quest landing together, with a banked run
  behind the first.

  A claim reads its row, runs `before_quest_claim`, then flips the row from
  completed to claimed and pays with an idempotency key built from
  `claim_count`. The first claim pays and re-arms the row onto the banked run,
  so the row is completed again, one `claim_count` on. A second claim that
  read the row before all that used to pass the flip (it matched on status
  alone) and pay with the key it read: the first run's. The ledger dropped
  that as a replay, and the banked run was re-armed away unpaid.

  The hook holds the first claim until the second has read the row, then
  holds the second until the first has paid and re-armed, so the interleaving
  happens on every run and on both adapters.
  """

  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Quests

  defmodule InterleavingHook do
    use Gamend.TestSupport.NoopHooks

    # First claim in: wait for the second to have read the row. Second in:
    # give the first time to pay and re-arm.
    @impl true
    def before_quest_claim(_user_id, _quest, progress) do
      coordinator = Application.fetch_env!(:gamend, :quest_claim_race)

      case Agent.get_and_update(coordinator, &{&1 + 1, &1 + 1}) do
        1 -> wait_until(fn -> Agent.get(coordinator, & &1) >= 2 end)
        _ -> Process.sleep(500)
      end

      {:ok, progress}
    end

    defp wait_until(fun, attempts \\ 200) do
      cond do
        fun.() ->
          :ok

        attempts == 0 ->
          raise "the second claim never reached its hook"

        true ->
          Process.sleep(10)
          wait_until(fun, attempts - 1)
      end
    end
  end

  setup do
    {:ok, coordinator} = Agent.start_link(fn -> 0 end)
    previous = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, InterleavingHook)
    Application.put_env(:gamend, :quest_claim_race, coordinator)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, :hooks_module, previous),
        else: Application.delete_env(:gamend_core, :hooks_module)

      Application.delete_env(:gamend, :quest_claim_race)
    end)

    {:ok, _} =
      Quests.create_quest(%{
        key: "treasure_race",
        title: "Treasure",
        reset: "repeat",
        objectives: [%{event: "found", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 50}]
      })

    :ok
  end

  test "a claim that read an earlier run never spends the banked one unpaid" do
    user = AccountsFixtures.user_fixture()

    # Two finds on a one-find quest: one run to claim, one banked behind it.
    {:ok, _} = Quests.report_event(user.id, "found", 2, %{})

    results =
      [
        fn -> Quests.claim(user.id, "treasure_race") end,
        fn -> Quests.claim(user.id, "treasure_race") end
      ]
      |> Enum.map(&Task.async/1)
      |> Task.await_many(10_000)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :already_claimed}, &1)) == 1

    # The banked run is still there to claim, and it pays.
    assert {:ok, _} = Quests.claim(user.id, "treasure_race")
    assert {:error, :not_completed} = Quests.claim(user.id, "treasure_race")

    assert Economy.balance(user.id, "gold") == 100,
           "two runs were earned; each must pay once"
  end
end
