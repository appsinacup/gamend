defmodule Gamend.CapRaceTest do
  @moduledoc """
  Count caps reached by writes landing together: a user's personal API
  tokens, a user's in-flight quest rows, a result's events.

  Each counted the rows and inserted only when there was room, with nothing
  between the count and the insert, so every write of a burst counted the
  same room and all of them inserted. Postgres only shows it; see
  `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.ApiTokens
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Quests
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestProgress
  alias Gamend.Results
  alias Gamend.Results.Event
  alias Gamend.SettingsHelpers

  @cap 3
  @racers 12

  setup do
    user = unboxed(fn -> AccountsFixtures.user_fixture() end)
    cleanup(fn -> Repo.delete_all(from u in User, where: u.id == ^user.id) end)
    %{user: user}
  end

  test "personal API tokens stop at max_api_tokens_per_user", %{user: user} do
    put_limit(:max_api_tokens_per_user, @cap)

    results =
      race(@racers, fn i ->
        ApiTokens.create(user, %{"name" => "ci #{i}", "expires_in_days" => 30})
      end)

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)
    assert Enum.count(results, &match?({:ok, _, _}, &1)) == @cap
    assert Enum.count(results, &(&1 == {:error, :limit_reached})) == @racers - @cap
    assert unboxed(fn -> ApiTokens.count(user.id) end) == @cap
  end

  test "in-flight quest rows stop at max_active_quests_per_user", %{user: user} do
    put_limit(:max_active_quests_per_user, @cap)
    keys = for i <- 1..@racers, do: "cap_race_#{System.unique_integer([:positive])}_#{i}"

    unboxed(fn ->
      for key <- keys do
        {:ok, _} =
          Quests.create_quest(%{
            key: key,
            title: key,
            objectives: [%{event: "cap_race", target: 10, params: %{"quest" => key}}]
          })
      end
    end)

    cleanup(fn -> Repo.delete_all(from q in Quest, where: q.key in ^keys) end)

    results =
      keys
      |> Enum.map(fn key ->
        fn -> Quests.report_event(user.id, "cap_race", 1, %{"quest" => key}) end
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)

    rows =
      unboxed(fn ->
        Repo.aggregate(
          from(p in QuestProgress, where: p.user_id == ^user.id and p.status == "active"),
          :count
        )
      end)

    assert rows == @cap, "#{rows} in-flight rows under a cap of #{@cap}"
  end

  test "a result's events stop at max_result_events", %{user: user} do
    put_limit(:max_result_events, @cap)
    {:ok, result} = unboxed(fn -> Results.start(user.id, "cap_race") end)

    results = race(@racers, fn i -> Results.record(result, "move", i) end)

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)
    assert Enum.count(results, &match?({:ok, %Event{}}, &1)) == @cap
    assert Enum.count(results, &(&1 == {:error, :too_many_events})) == @racers - @cap
    assert unboxed(fn -> Results.count_events(result.id) end) == @cap
  end

  test "an event recorded beside finish lands before the end or is refused", %{user: user} do
    {:ok, result} = unboxed(fn -> Results.start(user.id, "finish_race") end)

    records = for i <- 1..@racers, do: fn -> Results.record(result, "move", i) end
    [finished | recorded] = race([fn -> Results.finish(result) end | records])

    assert {:ok, %{ended_at: ended_at}} = finished
    refute Enum.any?(recorded, &match?({:raised, _}, &1)), inspect(recorded)
    assert Enum.all?(recorded, &(match?({:ok, %Event{}}, &1) or &1 == {:error, :ended}))

    # An event is timed when it is written, and the end inside the same lock.
    ended_ms = DateTime.diff(ended_at, result.started_at, :millisecond)

    late =
      unboxed(fn ->
        Repo.all(from e in Event, where: e.result_id == ^result.id, select: e.elapsed_ms)
      end)
      |> Enum.filter(&(&1 > ended_ms))

    assert late == [], "#{length(late)} events landed after the play ended"
  end

  defp put_limit(key, value) do
    previous = SettingsHelpers.get(:gamend_core, Gamend.Limits, key)
    SettingsHelpers.put(:gamend_core, Gamend.Limits, key, value)

    on_exit(fn ->
      if is_nil(previous),
        do: SettingsHelpers.delete(:gamend_core, Gamend.Limits, key),
        else: SettingsHelpers.put(:gamend_core, Gamend.Limits, key, previous)
    end)
  end
end
