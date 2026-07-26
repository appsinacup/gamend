defmodule GameServer.QuestsTest do
  use GameServer.DataCase

  alias GameServer.AccountsFixtures
  alias GameServer.Economy
  alias GameServer.Inventory
  alias GameServer.Quests
  alias GameServer.Quests.Quest
  alias GameServer.Quests.QuestProgress

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

      assert {:error, :already_claimed} = Quests.claim(user.id, "paid")
      assert Economy.balance(user.id, "gold") == 100
      assert Inventory.quantity(user.id, "loot_crate") == 2
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

      Repo.update_all(
        from(p in QuestProgress, where: p.quest_key == "prune_daily"),
        set: [inserted_at: old]
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
end
