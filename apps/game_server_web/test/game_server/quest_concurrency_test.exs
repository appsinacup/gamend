defmodule GameServer.QuestConcurrencyTest do
  @moduledoc """
  Quest progress is a read-modify-write inside `Lock.serialize/3`, so two
  players earning the same quest at once put two transactions on the same
  table.

  On SQLite that used to crash in production: a DEFERRED transaction that
  reads before it writes has to upgrade its lock, and SQLite answers a
  contended upgrade with `SQLITE_BUSY` immediately — `busy_timeout` only
  covers *waiting* for a lock, never *upgrading* one. The repo now opens
  transactions IMMEDIATE so the wait is honoured.
  """

  use GameServer.DataCase, async: false

  alias GameServer.AccountsFixtures
  alias GameServer.Quests

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

  test "the repo opens transactions in IMMEDIATE mode" do
    assert Keyword.get(
             Application.get_env(:game_server_core, GameServer.Repo),
             :default_transaction_mode
           ) == :immediate,
           "deferred transactions make read-modify-write paths fail under contention"
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
