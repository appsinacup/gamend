defmodule Gamend.QuestsTest do
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Inventory
  alias Gamend.Quests
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestProgress

  defp create_quest(attrs \\ %{}) do
    defaults = %{
      key: "quest_#{System.unique_integer([:positive])}",
      title: "Test Quest",
      objectives: [%{event: "test_event", target: 1}]
    }

    {:ok, quest} = Quests.create_quest(Map.merge(defaults, attrs))
    quest
  end

  defp user_fixture do
    AccountsFixtures.user_fixture()
  end

  describe "quest CRUD" do
    test "create_quest/1 creates with valid attrs" do
      attrs = %{
        key: "daily_win_3",
        title: "Win 3 matches",
        reset: "daily",
        category: "daily",
        objectives: [%{event: "match_won", target: 3, params: %{"mode" => "ranked"}}],
        rewards: [%{type: "currency", code: "gold", amount: 100}],
        auto_claim: false
      }

      assert {:ok, %Quest{} = quest} = Quests.create_quest(attrs)
      assert quest.key == "daily_win_3"
      assert quest.reset == "daily"
      assert quest.category == "daily"
      assert [objective] = quest.objectives
      assert objective.event == "match_won"
      assert objective.target == 3
      assert objective.params == %{"mode" => "ranked"}
      assert [reward] = quest.rewards
      assert reward.type == "currency"
      assert reward.code == "gold"
      assert reward.amount == 100
    end

    test "create_quest/1 validates required fields and reset" do
      assert {:error, changeset} = Quests.create_quest(%{})
      assert "can't be blank" in errors_on(changeset).key
      assert "can't be blank" in errors_on(changeset).title

      assert {:error, changeset} =
               Quests.create_quest(%{
                 key: "bad_reset",
                 title: "Bad",
                 reset: "fortnightly",
                 objectives: [%{event: "x"}]
               })

      assert "is invalid" in errors_on(changeset).reset
    end

    test "create_quest/1 requires an interval only for reset: interval" do
      assert {:error, changeset} =
               Quests.create_quest(%{
                 key: "no_interval",
                 title: "Missing",
                 reset: "interval",
                 objectives: [%{event: "x"}]
               })

      assert errors_on(changeset).reset_interval_days != []

      assert {:error, changeset} =
               Quests.create_quest(%{
                 key: "stray_interval",
                 title: "Stray",
                 reset: "daily",
                 reset_interval_days: 14,
                 objectives: [%{event: "x"}]
               })

      assert errors_on(changeset).reset_interval_days != []

      assert {:ok, quest} =
               Quests.create_quest(%{
                 key: "biweekly",
                 title: "Biweekly",
                 reset: "interval",
                 reset_interval_days: 14,
                 objectives: [%{event: "x"}]
               })

      assert quest.reset_interval_days == 14
    end

    test "create_quest/1 requires at least one objective" do
      assert {:error, changeset} =
               Quests.create_quest(%{key: "no_obj", title: "None", kind: "daily"})

      assert errors_on(changeset).objectives != []
    end

    test "create_quest/1 enforces unique key" do
      create_quest(%{key: "unique_key"})

      assert {:error, changeset} =
               Quests.create_quest(%{
                 key: "unique_key",
                 title: "Dupe",
                 reset: "daily",
                 category: "daily",
                 objectives: [%{event: "x"}]
               })

      assert "has already been taken" in errors_on(changeset).key
    end

    test "create_quest/1 rejects a window that ends before it starts" do
      assert {:error, changeset} =
               Quests.create_quest(%{
                 key: "bad_window",
                 title: "Window",
                 reset: "never",
                 objectives: [%{event: "x"}],
                 starts_at: ~U[2026-07-02 00:00:00Z],
                 ends_at: ~U[2026-07-01 00:00:00Z]
               })

      assert errors_on(changeset).ends_at != []
    end

    test "update_quest/2 and delete_quest/1 work and cascade progress" do
      quest = create_quest()
      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "test_event")

      assert {:ok, updated} = Quests.update_quest(quest, %{title: "Renamed"})
      assert updated.title == "Renamed"

      assert {:ok, _} = Quests.delete_quest(updated)
      assert Quests.get_quest_by_key(quest.key) == nil
      assert Repo.all(QuestProgress) == []
    end
  end

  describe "report_event/4" do
    test "advances a matching quest and completes at target" do
      quest = create_quest(%{objectives: [%{event: "enemy_killed", target: 3}]})
      user = user_fixture()

      {:ok, [progress]} = Quests.report_event(user.id, "enemy_killed")
      assert progress.status == "active"
      assert progress.objective_progress == %{"0" => 1}

      {:ok, [progress]} = Quests.report_event(user.id, "enemy_killed", 2)
      assert progress.status == "completed"
      assert progress.completed_at
      assert progress.quest_key == quest.key
    end

    test "completion sends a registered quest_completed notification" do
      quest = create_quest(%{objectives: [%{event: "boss_down", target: 1}]})
      user = user_fixture()
      :ok = Gamend.Notifications.subscribe(user.id)

      {:ok, [%{status: "completed"}]} = Quests.report_event(user.id, "boss_down")

      # String keys, like every other emitter: push routing and the realtime
      # payload both read `metadata["type"]`.
      assert_receive {:notification_created, notification}, 2_000
      assert notification.metadata["type"] == "quest_completed"
      assert notification.metadata["quest_key"] == quest.key
    end

    test "completes a multi-objective quest only when every objective is met" do
      create_quest(%{
        key: "multi",
        objectives: [%{event: "kill", target: 2}, %{event: "win", target: 1}]
      })

      user = user_fixture()

      {:ok, [p]} = Quests.report_event(user.id, "kill", 2)
      assert p.status == "active"

      {:ok, [p]} = Quests.report_event(user.id, "win")
      assert p.status == "completed"
      assert p.objective_progress == %{"0" => 2, "1" => 1}
    end

    test "objective params must all match the event meta" do
      create_quest(%{
        key: "desert_kills",
        objectives: [%{event: "kill", target: 1, params: %{"map" => "desert"}}]
      })

      user = user_fixture()

      {:ok, []} = Quests.report_event(user.id, "kill", 1, %{"map" => "forest"})
      {:ok, [p]} = Quests.report_event(user.id, "kill", 1, %{"map" => "desert", "extra" => true})
      assert p.status == "completed"
    end

    test "ignores events for unrelated quests, inactive quests and closed windows" do
      create_quest(%{key: "inactive", active: false, objectives: [%{event: "e1"}]})

      create_quest(%{
        key: "over",
        reset: "never",
        objectives: [%{event: "e1"}],
        starts_at: ~U[2020-01-01 00:00:00Z],
        ends_at: ~U[2020-02-01 00:00:00Z]
      })

      user = user_fixture()
      assert {:ok, []} = Quests.report_event(user.id, "e1")
      assert {:ok, []} = Quests.report_event(user.id, "no_such_event")
    end

    test "progress caps at the objective target" do
      create_quest(%{key: "capped", objectives: [%{event: "e", target: 2}]})
      user = user_fixture()

      {:ok, [p]} = Quests.report_event(user.id, "e", 100)
      assert p.objective_progress == %{"0" => 2}
    end

    test "completed quests stop advancing" do
      create_quest(%{key: "oneshot", objectives: [%{event: "e", target: 1}]})
      user = user_fixture()

      {:ok, [p]} = Quests.report_event(user.id, "e")
      assert p.status == "completed"

      assert {:ok, []} = Quests.report_event(user.id, "e")
    end

    test "chain quests only advance once the prerequisite is completed" do
      create_quest(%{key: "step1", objectives: [%{event: "win", target: 1}]})

      create_quest(%{
        key: "step2",
        prerequisite_quest_key: "step1",
        objectives: [%{event: "win", target: 2}]
      })

      user = user_fixture()

      # First win completes step1 only; step2 was still locked when dispatched.
      {:ok, advanced} = Quests.report_event(user.id, "win")
      assert Enum.map(advanced, & &1.quest_key) == ["step1"]

      {:ok, advanced} = Quests.report_event(user.id, "win")
      assert Enum.map(advanced, & &1.quest_key) == ["step2"]
    end

    test "chain/2 returns every tier in order with per-tier status" do
      create_quest(%{key: "tier1", objectives: [%{event: "win", target: 1}]})

      create_quest(%{
        key: "tier2",
        prerequisite_quest_key: "tier1",
        objectives: [%{event: "win", target: 1}]
      })

      create_quest(%{
        key: "tier3",
        prerequisite_quest_key: "tier2",
        objectives: [%{event: "win", target: 5}]
      })

      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "win")

      # Same chain regardless of which member is asked about — including a
      # tier the quest list itself would still hide from this user.
      for key <- ["tier1", "tier2", "tier3"] do
        entries = Quests.chain(user.id, key)
        assert Enum.map(entries, & &1.quest.key) == ["tier1", "tier2", "tier3"]
        assert Enum.map(entries, & &1.tier) == [1, 2, 3]
      end

      [t1, t2, t3] = Quests.chain(user.id, "tier2")

      assert t1.progress.status == "completed"
      assert t1.claimable
      refute t1.locked

      # tier1 is done, so tier2 is unlocked even with no progress row yet.
      assert t2.progress == nil
      refute t2.locked

      assert t3.locked
    end

    test "chain/2 without a user locks everything past the root" do
      create_quest(%{key: "solo_a", objectives: [%{event: "win", target: 1}]})

      create_quest(%{
        key: "solo_b",
        prerequisite_quest_key: "solo_a",
        objectives: [%{event: "win", target: 1}]
      })

      assert [a, b] = Quests.chain(nil, "solo_b")
      refute a.locked
      assert b.locked
      assert a.progress == nil and b.progress == nil
    end

    test "chain/2 returns [] for unknown keys and a single entry for unchained quests" do
      quest = create_quest(%{})
      assert Quests.chain(nil, "no_such_quest") == []
      assert [%{quest: %{key: key}, tier: 1}] = Quests.chain(nil, quest.key)
      assert key == quest.key
    end

    test "an event for a quest deleted as it is read advances nothing and writes no progress" do
      # An event no other quest listens to, so the catalogue read misses the
      # cache and really selects from quests.
      event = "vanishing_#{System.unique_integer([:positive])}"
      quest = create_quest(%{objectives: [%{event: event, target: 2}]})
      user = user_fixture()
      test_pid = self()
      handler = {__MODULE__, :delete_quest_after_read, System.unique_integer()}

      :telemetry.attach(
        handler,
        [:gamend, :repo, :query],
        fn _event, _measurements, meta, _config ->
          if self() == test_pid and meta[:source] == "quests" and !Process.get(:quest_deleted) do
            Process.put(:quest_deleted, true)
            Repo.delete_all(from q in Quest, where: q.id == ^quest.id)
          end
        end,
        nil
      )

      result = Quests.report_event(user.id, event)
      :telemetry.detach(handler)

      assert Process.get(:quest_deleted)
      assert result == {:ok, []}
      assert Repo.get(Quest, quest.id) == nil
      assert Repo.all(from p in QuestProgress, where: p.user_id == ^user.id) == []
    end
  end

  describe "periods" do
    test "period_key/2 buckets by reset in UTC" do
      now = ~U[2026-07-24 10:00:00Z]
      assert Quests.period_key("daily", now) == "2026-07-24"
      assert Quests.period_key("weekly", now) == "2026-W30"
      assert Quests.period_key("monthly", now) == "2026-07"
      assert Quests.period_key("never", now) == "static"
    end

    test "period_key/2 buckets interval resets by cadence" do
      quest = %Quest{reset: "interval", reset_interval_days: 14}

      # Buckets are floor(days-since-epoch / cadence): stable inside a window,
      # incrementing exactly once per cadence.
      assert Quests.period_key(quest, ~U[2026-07-24 10:00:00Z]) == "I14-1475"
      assert Quests.period_key(quest, ~U[2026-07-29 23:59:59Z]) == "I14-1475"
      assert Quests.period_key(quest, ~U[2026-07-30 00:00:00Z]) == "I14-1476"
      assert Quests.period_key(quest, ~U[2026-08-13 00:00:00Z]) == "I14-1477"

      # A different cadence buckets independently.
      weekly_ish = %Quest{reset: "interval", reset_interval_days: 7}
      assert Quests.period_key(weekly_ish, ~U[2026-07-24 10:00:00Z]) == "I7-2951"
    end

    test "a new daily period gets a fresh progress row" do
      create_quest(%{key: "daily_q", reset: "daily", objectives: [%{event: "e", target: 5}]})
      user = user_fixture()

      {:ok, [p]} = Quests.report_event(user.id, "e", 5)
      assert p.status == "completed"

      # Roll the period: rewrite the row into yesterday's bucket.
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

      Repo.update_all(QuestProgress, set: [period_key: yesterday])

      {:ok, [fresh]} = Quests.report_event(user.id, "e")
      assert fresh.status == "active"
      assert fresh.objective_progress == %{"0" => 1}
      assert Repo.aggregate(QuestProgress, :count) == 2
    end
  end

  describe "claim/3 and rewards" do
    test "claim pays rewards exactly once, double-claim never double-pays" do
      create_quest(%{
        key: "paid",
        objectives: [%{event: "e", target: 1}],
        rewards: [
          %{type: "currency", code: "gold", amount: 100},
          %{type: "item", code: "loot_crate", amount: 2}
        ]
      })

      user = user_fixture()
      {:ok, [_p]} = Quests.report_event(user.id, "e")

      assert {:ok, %{progress: progress, rewards: rewards}} = Quests.claim(user.id, "paid")
      assert progress.status == "claimed"
      assert progress.rewards_granted_at
      assert length(rewards) == 2

      assert Economy.balance(user.id, "gold") == 100
      assert Inventory.quantity(user.id, "loot_crate") == 2

      # The wallet row names its quest — every payout used to be an
      # indistinguishable "quest_reward".
      assert [entry] = Economy.list_ledger(user_id: user.id)
      assert entry.reason == "quest_reward:paid"

      assert {:error, :already_claimed} = Quests.claim(user.id, "paid")
      assert Economy.balance(user.id, "gold") == 100
      assert Inventory.quantity(user.id, "loot_crate") == 2
    end

    test "a repeat quest re-arms on claim and pays every time" do
      # The whole point of the reset: an endless objective (find the treasure,
      # then the next one) pays per completion, not per calendar period.
      create_quest(%{
        key: "endless",
        reset: "repeat",
        objectives: [%{event: "found", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 50}]
      })

      user = user_fixture()

      for round <- 1..3 do
        {:ok, [progress]} = Quests.report_event(user.id, "found")
        assert progress.status == "completed", "round #{round} did not complete"

        assert {:ok, %{progress: claimed}} = Quests.claim(user.id, "endless")
        assert claimed.claim_count == round
        # Re-armed in place, ready for the next find without waiting on a clock.
        assert claimed.status == "active"
        assert claimed.objective_progress == %{}
        assert is_nil(claimed.completed_at)

        # This is the assertion the whole change hangs on: without claim_count
        # in the idempotency key, rounds 2 and 3 dedupe and pay nothing, and a
        # deduped grant reports success.
        assert Economy.balance(user.id, "gold") == 50 * round
      end
    end

    test "a repeat quest is not claimable again until it is finished again" do
      create_quest(%{
        key: "endless_gate",
        reset: "repeat",
        objectives: [%{event: "found", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 50}]
      })

      user = user_fixture()
      {:ok, [_p]} = Quests.report_event(user.id, "found")
      assert {:ok, _} = Quests.claim(user.id, "endless_gate")

      assert {:error, :not_completed} = Quests.claim(user.id, "endless_gate")
      assert Economy.balance(user.id, "gold") == 50
    end

    test "rearm_repeat_quests heals a claim that died before re-arming" do
      # Only reachable by crashing between granting and re-arming; without the
      # heal the player sits on a quest that never comes back.
      create_quest(%{
        key: "endless_crash",
        reset: "repeat",
        objectives: [%{event: "found", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 50}]
      })

      user = user_fixture()
      {:ok, [_p]} = Quests.report_event(user.id, "found")
      assert {:ok, %{progress: claimed}} = Quests.claim(user.id, "endless_crash")

      # Put it back into the stranded shape the crash would leave behind.
      Repo.update_all(
        from(p in QuestProgress, where: p.id == ^claimed.id),
        set: [status: "claimed", rewards_granted_at: DateTime.utc_now(:second)]
      )

      assert Quests.rearm_repeat_quests(user_id: user.id) == 1
      progress = Repo.get_uuid(QuestProgress, claimed.id)
      assert progress.status == "active"
      assert progress.objective_progress == %{}
    end

    test "a first claim keeps the original reward idempotency key" do
      # Changing the key shape for every quest would make recover_pending_rewards
      # retry a mid-grant row against a key the first attempt never wrote, and
      # pay a second time for work already done.
      create_quest(%{
        key: "once",
        objectives: [%{event: "e", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 10}]
      })

      user = user_fixture()
      {:ok, [_p]} = Quests.report_event(user.id, "e")
      assert {:ok, %{progress: progress}} = Quests.claim(user.id, "once")
      assert progress.claim_count == 0
      assert Economy.balance(user.id, "gold") == 10

      # Re-grant under the same key: it must dedupe, not pay again.
      Repo.update_all(
        from(p in QuestProgress, where: p.id == ^progress.id),
        set: [rewards_granted_at: nil, claimed_at: DateTime.add(DateTime.utc_now(:second), -3600)]
      )

      _ = Quests.recover_pending_rewards(user_id: user.id)
      assert Economy.balance(user.id, "gold") == 10
    end

    test "claim requires a completed quest" do
      create_quest(%{key: "not_done", objectives: [%{event: "e", target: 2}]})
      user = user_fixture()

      assert {:error, :not_completed} = Quests.claim(user.id, "not_done")
      {:ok, [_p]} = Quests.report_event(user.id, "e")
      assert {:error, :not_completed} = Quests.claim(user.id, "not_done")
      assert {:error, :quest_not_found} = Quests.claim(user.id, "missing")
    end

    test "auto_claim quests pay on completion without a claim step" do
      create_quest(%{
        key: "auto",
        auto_claim: true,
        objectives: [%{event: "e", target: 1}],
        rewards: [%{type: "currency", code: "gems", amount: 5}]
      })

      user = user_fixture()
      {:ok, [_p]} = Quests.report_event(user.id, "e")

      progress = Quests.get_progress(user.id, "auto")
      assert progress.status == "claimed"
      assert Economy.balance(user.id, "gems") == 5
    end

    test "recover_pending_rewards/1 heals a claimed row whose grants never ran" do
      create_quest(%{
        key: "crashed",
        objectives: [%{event: "e", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 50}]
      })

      user = user_fixture()
      {:ok, [p]} = Quests.report_event(user.id, "e")

      # Simulate a claim that died after the status transition, before grants.
      old = DateTime.add(DateTime.utc_now(:second), -120)

      Repo.update_all(
        from(qp in QuestProgress, where: qp.id == ^p.id),
        set: [status: "claimed", claimed_at: old]
      )

      assert Economy.balance(user.id, "gold") == 0
      assert Quests.recover_pending_rewards() == 1
      assert Economy.balance(user.id, "gold") == 50
      assert Repo.get(QuestProgress, p.id).rewards_granted_at

      # Idempotent: running again grants nothing extra.
      assert Quests.recover_pending_rewards() == 0
      assert Economy.balance(user.id, "gold") == 50
    end
  end

  describe "player reads" do
    test "list_user_quests/2 returns progress and claimable flag" do
      create_quest(%{key: "visible", objectives: [%{event: "e", target: 1}]})
      user = user_fixture()

      [entry] = Quests.list_user_quests(user.id)
      assert entry.quest.key == "visible"
      assert entry.progress == nil
      refute entry.claimable

      {:ok, [_p]} = Quests.report_event(user.id, "e")

      [entry] = Quests.list_user_quests(user.id)
      assert entry.progress.status == "completed"
      assert entry.claimable
      assert Quests.claimable_count(user.id) == 1
      assert Quests.count_user_quests(user.id) == 1
    end

    test "user_quest_page/2 is the list, its count and the tabs, from one read" do
      create_quest(%{key: "pg_a", category: "learn", objectives: [%{event: "e", target: 1}]})

      create_quest(%{
        key: "pg_b",
        category: "learn",
        prerequisite_quest_key: "pg_a",
        objectives: [%{event: "e", target: 2}]
      })

      create_quest(%{
        key: "pg_c",
        category: "daily",
        reset: "daily",
        objectives: [%{event: "f", target: 1}]
      })

      for i <- 1..3 do
        create_quest(%{
          key: "pg_g#{i}",
          category: "explore",
          group_key: "pg_g",
          objectives: [%{event: "g", target: 1}]
        })
      end

      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "e")

      for opts <- [
            [],
            [category: "learn"],
            [status: "claimable"],
            [group: "pg_g"],
            [drop_groups: ["pg_g"]],
            [page: 2, page_size: 2]
          ] do
        page = Quests.user_quest_page(user.id, opts)
        assert page.entries == Quests.list_user_quests(user.id, opts), inspect(opts)

        assert page.total ==
                 Quests.count_user_quests(user.id, Keyword.drop(opts, [:page, :page_size]))

        assert page.categories == Quests.visible_categories(user.id)
      end

      # The pending-rewards heal, then the user's progress read once (no repeat
      # quest here, so that heal has nothing to ask). Listing, counting and
      # the tabs separately read it three times (each was two queries before
      # this period's rows and the done prerequisites became one).
      assert {_, 2} = quest_progress_queries(fn -> Quests.user_quest_page(user.id) end)

      assert {_, 4} =
               quest_progress_queries(fn ->
                 {Quests.list_user_quests(user.id), Quests.count_user_quests(user.id),
                  Quests.visible_categories(user.id)}
               end)
    end

    test "hidden quests are listed as teasers and stay listed once earned" do
      create_quest(%{key: "secret", hidden: true, objectives: [%{event: "e", target: 1}]})
      user = user_fixture()

      # Listed even before earning it (callers obscure the details), the way
      # hidden achievements were teased.
      assert [%{quest: %{key: "secret"}, progress: nil}] = Quests.list_user_quests(user.id)

      {:ok, [_p]} = Quests.report_event(user.id, "e")

      assert [%{quest: %{key: "secret"}, progress: %{status: "completed"}}] =
               Quests.list_user_quests(user.id)
    end

    test "a group lists as one entry and opens to its members" do
      for {id, order} <- [{"es", 2}, {"ro", 1}, {"pl", 3}] do
        create_quest(%{
          key: "chart_#{id}",
          group_key: "exploration",
          sort_order: order,
          objectives: [%{event: "city_visited", target: 5, params: %{"country" => id}}]
        })
      end

      create_quest(%{key: "solo", objectives: [%{event: "other", target: 1}]})
      user = user_fixture()

      # One entry for the whole group, however many countries exist, plus the
      # ungrouped quest untouched.
      entries = Quests.list_user_quests(user.id)
      assert length(entries) == 2
      group = Enum.find(entries, &(&1.quest.group_key == "exploration"))
      assert group.group_size == 3
      assert group.collapsed

      # The representative is the one worth acting on, not whatever sorted first.
      {:ok, _} = Quests.report_event(user.id, "city_visited", 3, %{"country" => "pl"})
      group = Enum.find(Quests.list_user_quests(user.id), &(&1.quest.group_key == "exploration"))
      assert group.quest.key == "chart_pl"
      assert group.group_size == 3

      # Opening it lists every member; the ungrouped quest still comes along.
      opened = Quests.list_user_quests(user.id, group: "exploration")
      assert length(opened) == 4
      assert Enum.count(opened, &(&1.quest.group_key == "exploration")) == 3
    end

    test "a chain inside a group collapses as a chain first" do
      create_quest(%{key: "t1", group_key: "g", objectives: [%{event: "e", target: 1}]})

      create_quest(%{
        key: "t2",
        group_key: "g",
        prerequisite_quest_key: "t1",
        objectives: [%{event: "e", target: 2}]
      })

      create_quest(%{key: "solo", group_key: "g", objectives: [%{event: "f", target: 1}]})
      user = user_fixture()

      # The chain is one member, not two: t2 is not even reachable yet. So the
      # group stands for 2 things (the chain and the solo quest), not 3.
      [entry] = Quests.list_user_quests(user.id)
      assert entry.group_size == 2

      opened = Quests.list_user_quests(user.id, group: "g")
      assert Enum.map(opened, & &1.quest.key) |> Enum.sort() == ["solo", "t1"]
    end

    test "group/2 returns every member with the viewer's progress" do
      create_quest(%{
        key: "g_a",
        group_key: "g",
        sort_order: 2,
        objectives: [%{event: "e", target: 2}]
      })

      create_quest(%{
        key: "g_b",
        group_key: "g",
        sort_order: 1,
        objectives: [%{event: "f", target: 2}]
      })

      create_quest(%{key: "loose", objectives: [%{event: "e", target: 1}]})

      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "e", 1)

      members = Quests.group(user.id, "g")

      # Every member, sort_order first, and only members.
      assert Enum.map(members, & &1.quest.key) == ["g_b", "g_a"]

      assert Enum.find(members, &(&1.quest.key == "g_a")).progress.objective_progress == %{
               "0" => 1
             }

      assert Enum.find(members, &(&1.quest.key == "g_b")).progress == nil
      assert Quests.group(user.id, "nope") == []
    end

    test "group/2 leaves out what the list would not show either" do
      now = DateTime.utc_now(:second)

      create_quest(%{key: "open", group_key: "g", objectives: [%{event: "e", target: 1}]})

      create_quest(%{
        key: "over",
        group_key: "g",
        ends_at: DateTime.add(now, -60, :second),
        objectives: [%{event: "e", target: 1}]
      })

      create_quest(%{key: "gate", objectives: [%{event: "f", target: 1}]})

      create_quest(%{
        key: "locked",
        group_key: "g",
        prerequisite_quest_key: "gate",
        objectives: [%{event: "e", target: 1}]
      })

      user = user_fixture()

      # Otherwise the badge counts one thing and opening the card reveals three.
      assert Enum.map(Quests.group(user.id, "g"), & &1.quest.key) == ["open"]

      assert Enum.find(Quests.list_user_quests(user.id), &(&1.quest.group_key == "g")).group_size ==
               1

      {:ok, _} = Quests.report_event(user.id, "f", 1)
      assert Enum.map(Quests.group(user.id, "g"), & &1.quest.key) == ["locked", "open"]
    end

    test "an opened group does not expand the other groups" do
      create_quest(%{key: "a1", group_key: "a", objectives: [%{event: "e", target: 1}]})
      create_quest(%{key: "a2", group_key: "a", objectives: [%{event: "e", target: 1}]})
      create_quest(%{key: "b1", group_key: "b", objectives: [%{event: "f", target: 1}]})
      create_quest(%{key: "b2", group_key: "b", objectives: [%{event: "f", target: 1}]})
      create_quest(%{key: "solo", objectives: [%{event: "g", target: 1}]})

      user = user_fixture()
      opened = Quests.list_user_quests(user.id, group: "a")

      # "a" in full, "b" still one entry, the ungrouped quest along. Only the
      # entry standing for "b" is collapsed: a listed member is itself, at the
      # same group size.
      assert Enum.map(opened, & &1.quest.key) == ["a1", "a2", "b1", "solo"]
      assert Enum.map(opened, &Map.get(&1, :group_size)) == [2, 2, 2, nil]
      assert Enum.map(opened, &Map.get(&1, :collapsed, false)) == [false, false, true, false]
    end

    test "dropped groups are off the list, collapsed or opened" do
      create_quest(%{key: "a1", group_key: "a", objectives: [%{event: "e", target: 1}]})
      create_quest(%{key: "a2", group_key: "a", objectives: [%{event: "e", target: 1}]})
      create_quest(%{key: "b1", group_key: "b", objectives: [%{event: "f", target: 1}]})
      create_quest(%{key: "c1", group_key: "c", objectives: [%{event: "f", target: 1}]})
      create_quest(%{key: "solo", objectives: [%{event: "g", target: 1}]})

      user = user_fixture()

      # What a page with a selector over "a" and "b" lists once "a" is picked:
      # "a" in full, "b" gone, "c" (not the selector's) still its card.
      picked = Quests.list_user_quests(user.id, group: "a", drop_groups: ["b"])
      assert Enum.map(picked, & &1.quest.key) == ["a1", "a2", "c1", "solo"]
      assert Quests.count_user_quests(user.id, group: "a", drop_groups: ["b"]) == 4

      # Nothing picked behind that selector: both its groups gone.
      none = Quests.list_user_quests(user.id, drop_groups: ["a", "b"])
      assert Enum.map(none, & &1.quest.key) == ["c1", "solo"]
      assert Quests.count_user_quests(user.id, drop_groups: ["a", "b"]) == 2
    end

    test "groups/2 offers each group once, in list order, under its title" do
      create_quest(%{
        key: "b1",
        group_key: "b",
        group_title: "Bravo",
        sort_order: 2,
        objectives: [%{event: "f", target: 1}]
      })

      create_quest(%{
        key: "a1",
        group_key: "a",
        group_title: "Alpha",
        sort_order: 1,
        category: "learn",
        objectives: [%{event: "e", target: 1}]
      })

      create_quest(%{
        key: "a2",
        group_key: "a",
        group_title: "Alpha",
        sort_order: 3,
        category: "learn",
        objectives: [%{event: "e", target: 1}]
      })

      create_quest(%{key: "solo", objectives: [%{event: "g", target: 1}]})
      user = user_fixture()

      assert Quests.groups(user.id) == [%{key: "a", title: "Alpha"}, %{key: "b", title: "Bravo"}]
      assert Quests.groups(user.id, "learn") == [%{key: "a", title: "Alpha"}]
      assert Quests.groups(nil) == [%{key: "a", title: "Alpha"}, %{key: "b", title: "Bravo"}]
      assert Quests.groups(user.id, "daily") == []
    end

    test "a chain longer than 20 tiers is still ONE chain, in order" do
      # 52 course units chain end to end. A hop cap of 20 split them into three
      # separate "chains" and sorted every tier past the cap equal.
      for tier <- 1..52 do
        create_quest(%{
          key: "unit_#{tier}",
          sort_order: tier,
          prerequisite_quest_key: if(tier > 1, do: "unit_#{tier - 1}"),
          objectives: [%{event: "mastered", target: 1, params: %{"unit" => tier}}]
        })
      end

      user = user_fixture()

      assert [%{quest: %{key: "unit_1"}}] = Quests.list_user_quests(user.id)

      chain = Quests.chain(user.id, "unit_52")
      assert length(chain) == 52
      assert Enum.map(chain, & &1.tier) == Enum.to_list(1..52)
      assert List.last(chain).quest.key == "unit_52"
    end

    test "a prerequisite cycle terminates instead of hanging" do
      # The hop cap was really a cycle guard. Nothing stops an operator wiring
      # A -> B -> A by hand, and an unbounded walk would spin forever.
      create_quest(%{key: "loop_a", objectives: [%{event: "e", target: 1}]})

      create_quest(%{
        key: "loop_b",
        prerequisite_quest_key: "loop_a",
        objectives: [%{event: "e", target: 1}]
      })

      {:ok, a} =
        Quests.get_quest_by_key("loop_a")
        |> Quests.update_quest(%{prerequisite_quest_key: "loop_b"})

      assert a.prerequisite_quest_key == "loop_b"

      user = user_fixture()

      assert is_list(Quests.list_user_quests(user.id))
      assert is_list(Quests.chain(user.id, "loop_a"))
    end

    test "a chain lists as one entry: the tier the player can act on" do
      create_quest(%{key: "first", objectives: [%{event: "win", target: 1}]})

      create_quest(%{
        key: "second",
        prerequisite_quest_key: "first",
        objectives: [%{event: "win", target: 2}]
      })

      user = user_fixture()

      # Untouched chain: only the first tier.
      assert Enum.map(Quests.list_user_quests(user.id), & &1.quest.key) == ["first"]

      # Completed but unclaimed: still the first tier — the claim is the
      # player's pending action, and showing tier two too would list the
      # chain twice.
      {:ok, _} = Quests.report_event(user.id, "win")
      assert [%{quest: %{key: "first"}, claimable: true}] = Quests.list_user_quests(user.id)

      # Claiming advances the card to the next tier.
      {:ok, _} = Quests.claim(user.id, "first")
      assert Enum.map(Quests.list_user_quests(user.id), & &1.quest.key) == ["second"]

      # Fully claimed chain: the final tier stands for it.
      {:ok, _} = Quests.report_event(user.id, "win")
      {:ok, _} = Quests.report_event(user.id, "win")
      {:ok, _} = Quests.claim(user.id, "second")

      assert [%{quest: %{key: "second"}, progress: %{status: "claimed"}}] =
               Quests.list_user_quests(user.id)
    end
  end

  describe "admin operations" do
    test "admin_complete/2 force-completes and admin_reset/2 clears" do
      create_quest(%{key: "forced", objectives: [%{event: "e", target: 10}]})
      user = user_fixture()

      assert {:ok, progress} = Quests.admin_complete(user.id, "forced")
      assert progress.status == "completed"
      assert progress.objective_progress == %{"0" => 10}

      assert {:error, :already_completed} = Quests.admin_complete(user.id, "forced")

      assert {:ok, _} = Quests.admin_reset(user.id, "forced")
      assert Quests.get_progress(user.id, "forced") == nil
      assert {:ok, :not_found} = Quests.admin_reset(user.id, "forced")
    end

    test "admin_claim/2 claims on the user's behalf" do
      create_quest(%{
        key: "admin_claimed",
        objectives: [%{event: "e", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 10}]
      })

      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "e")

      assert {:ok, %{progress: %{status: "claimed"}}} =
               Quests.admin_claim(user.id, "admin_claimed")

      assert Economy.balance(user.id, "gold") == 10
    end

    test "list_progress/1 and count_progress/1 filter by quest, status and user" do
      create_quest(%{key: "filter_me", objectives: [%{event: "e", target: 2}]})
      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "e")

      assert [row] = Quests.list_progress(quest_key: "filter_me")
      assert row.user_id == user.id
      assert Quests.count_progress(quest_key: "filter_me", status: "active") == 1
      assert Quests.count_progress(quest_key: "filter_me", status: "claimed") == 0
      assert Quests.count_progress(user_id: user.id) == 1
    end

    test "funnel/1 and dashboard_stats/0 count statuses" do
      create_quest(%{key: "funneled", objectives: [%{event: "e", target: 1}]})
      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "e")

      assert Quests.funnel("funneled") == %{"completed" => 1}

      stats = Quests.dashboard_stats()
      assert stats.definitions >= 1
      assert stats.completions_today >= 1
      assert stats.claimable_now >= 1
    end
  end

  describe "retention" do
    test "prune_old_periods/0 removes old daily rows but keeps static ones" do
      create_quest(%{key: "prune_daily", reset: "daily", objectives: [%{event: "e"}]})
      create_quest(%{key: "prune_static", objectives: [%{event: "e"}]})
      user = user_fixture()
      {:ok, _} = Quests.report_event(user.id, "e")

      old = DateTime.add(DateTime.utc_now(:second), -100 * 86_400)

      # Claimed: a completed row waits for its claim and is never pruned.
      Repo.update_all(
        from(p in QuestProgress, where: p.quest_key == "prune_daily"),
        set: [inserted_at: old, status: "claimed"]
      )

      Repo.update_all(
        from(p in QuestProgress, where: p.quest_key == "prune_static"),
        set: [inserted_at: old]
      )

      assert Quests.prune_old_periods() == 1
      assert Quests.get_progress(user.id, "prune_static")
      assert Quests.get_progress(user.id, "prune_daily") == nil
    end
  end

  describe "host visibility filter" do
    # The host filter is a module function; this one hides any quest whose
    # metadata says "members only" unless the viewer is the named member.
    def only_for_member(user_id, quests) do
      Enum.reject(quests, fn q ->
        q.metadata["members_only"] == true and q.metadata["member"] != user_id
      end)
    end

    setup do
      original = Application.get_env(:gamend_core, :quest_visibility_filter)
      on_exit(fn -> restore(original) end)
      :ok
    end

    defp restore(nil), do: Application.delete_env(:gamend_core, :quest_visibility_filter)
    defp restore(value), do: Application.put_env(:gamend_core, :quest_visibility_filter, value)

    test "hides quests from listings, counts and categories — but not from progress" do
      member = user_fixture()
      other = user_fixture()
      Application.put_env(:gamend_core, :quest_visibility_filter, {__MODULE__, :only_for_member})

      create_quest(%{key: "vis_open", category: "open"})

      create_quest(%{
        key: "vis_members",
        category: "members",
        metadata: %{"members_only" => true, "member" => member.id}
      })

      keys = fn user_id -> user_id |> Quests.list_user_quests() |> Enum.map(& &1.quest.key) end
      assert "vis_members" in keys.(member.id)
      refute "vis_members" in keys.(other.id)
      assert "vis_open" in keys.(other.id)
      assert Quests.count_user_quests(other.id) == length(keys.(other.id))
      assert "members" in Quests.visible_categories(member.id)
      refute "members" in Quests.visible_categories(other.id)
      # The signed-out catalog asks the host with nil.
      refute "members" in Quests.visible_categories(nil)

      # Progress is not gated: the outsider still advances it, unseen.
      {:ok, _} = Quests.report_event(other.id, "test_event", 1)
      assert Quests.get_progress(other.id, "vis_members").status == "completed"
    end

    test "with no filter configured every active quest is visible" do
      Application.delete_env(:gamend_core, :quest_visibility_filter)
      user = user_fixture()
      create_quest(%{key: "vis_plain", metadata: %{"members_only" => true}})

      assert "vis_plain" in Enum.map(Quests.list_user_quests(user.id), & &1.quest.key)
    end
  end

  # How many `quest_progress` queries this process sends while `fun` runs.
  defp quest_progress_queries(fun) do
    ref = make_ref()
    handler = "quests-test-#{inspect(ref)}"

    :ok =
      :telemetry.attach(
        handler,
        [:gamend, :repo, :query],
        &__MODULE__.count_query/4,
        {self(), ref}
      )

    try do
      result = fun.()
      {result, drain_queries(ref, 0)}
    after
      :telemetry.detach(handler)
    end
  end

  @doc false
  def count_query(_event, _measurements, metadata, {pid, ref}) do
    if self() == pid and metadata[:source] == "quest_progress", do: send(pid, {ref, :query})
  end

  defp drain_queries(ref, count) do
    receive do
      {^ref, :query} -> drain_queries(ref, count + 1)
    after
      0 -> count
    end
  end
end
