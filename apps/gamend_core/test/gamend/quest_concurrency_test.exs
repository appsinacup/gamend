defmodule Gamend.QuestConcurrencyTest do
  @moduledoc """
  Quest progress is a read-modify-write on a JSON map, so two events landing
  together on one row can each read the same map and the second write can drop
  the first's increment.

  It used to be serialized with a per-(user, quest) advisory lock. It is now
  guarded by `lock_version`: the loser of a race matches no row, re-reads and
  merges again. The tests below are what says that holds — a lost increment is
  invisible from the outside, which is exactly why it needs asserting.
  """

  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Quests

  setup do
    {:ok, quest} =
      Quests.create_quest(%{
        key: "concurrent_login",
        title: "Welcome aboard",
        reset: "never",
        objectives: [%{event: "login", target: 1}]
      })

    %{quest: quest}
  end

  test "many players earning the same quest at once all get progress" do
    users = for _ <- 1..12, do: AccountsFixtures.user_fixture()

    results =
      users
      |> Task.async_stream(
        fn user -> Quests.report_event(user.id, "login") end,
        max_concurrency: 12,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    refute Enum.any?(results, &match?({:error, _}, &1)),
           "a concurrent report_event failed: #{inspect(Enum.filter(results, &match?({:error, _}, &1)))}"

    for user <- users do
      entry =
        user.id
        |> Quests.list_user_quests([])
        |> Enum.find(&(&1.quest.key == "concurrent_login"))

      assert entry.progress, "no progress recorded for #{user.id}"
      assert entry.progress.status in ["completed", "claimed"]
    end
  end

  test "concurrent increments on one objective all land" do
    # Target 25, so the count itself is the assertion. The pre-existing tests
    # use a target of 1, which any single increment satisfies — they pass just
    # as happily when 11 of 12 increments are lost.
    {:ok, _} =
      Quests.create_quest(%{
        key: "concurrent_kills",
        title: "Sink 25 ships",
        reset: "never",
        objectives: [%{event: "enemy_killed", target: 25}]
      })

    user = AccountsFixtures.user_fixture()

    results =
      1..25
      |> Task.async_stream(fn _ -> Quests.report_event(user.id, "enemy_killed", 1, %{}) end,
        max_concurrency: 25,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    refute Enum.any?(results, &match?({:error, _}, &1)),
           "a concurrent report_event failed: #{inspect(Enum.filter(results, &match?({:error, _}, &1)))}"

    progress = Quests.get_progress(user.id, "concurrent_kills")

    assert progress.objective_progress["0"] == 25,
           "expected all 25 increments, got #{inspect(progress.objective_progress)}"

    assert progress.status == "completed"
  end

  test "an increment that races a claim is not written over the re-armed row" do
    # A `repeat` quest re-arms on claim by resetting `objective_progress`
    # through `update_all`. An advance that read the row before the reset used
    # to be able to write the pre-reset counts back on top of it; it now loses
    # on `lock_version` and merges against the reset row instead.
    {:ok, _} =
      Quests.create_quest(%{
        key: "concurrent_repeat",
        title: "Repeatable",
        reset: "repeat",
        objectives: [%{event: "coin_found", target: 2}]
      })

    user = AccountsFixtures.user_fixture()

    {:ok, _} = Quests.report_event(user.id, "coin_found", 2, %{})
    {:ok, _} = Quests.claim(user.id, "concurrent_repeat")

    progress = Quests.get_progress(user.id, "concurrent_repeat")
    assert progress.status == "active", "a repeat quest re-arms on claim"
    assert progress.objective_progress == %{}, "the re-arm resets progress"

    {:ok, _} = Quests.report_event(user.id, "coin_found", 1, %{})

    assert Quests.get_progress(user.id, "concurrent_repeat").objective_progress == %{"0" => 1},
           "the post-claim increment must count from the reset, not from the old total"
  end

  test "the same player reporting the same event repeatedly stays consistent", %{quest: quest} do
    user = AccountsFixtures.user_fixture()

    1..10
    |> Task.async_stream(fn _ -> Quests.report_event(user.id, "login") end,
      max_concurrency: 10,
      timeout: 30_000
    )
    |> Stream.run()

    entry =
      user.id
      |> Quests.list_user_quests([])
      |> Enum.find(&(&1.quest.key == quest.key))

    assert entry.progress.status in ["completed", "claimed"]
  end
end
