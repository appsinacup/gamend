defmodule Gamend.AnalyticsTest do
  use Gamend.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Analytics
  alias Gamend.Analytics.ActivityDay
  alias Gamend.Analytics.Event
  alias Gamend.Repo

  @today ~D[2026-08-16]

  defp at(day), do: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")

  # Fixtures register "now"; cohort tests need users who joined on a chosen day.
  defp user_registered_on(day) do
    user = AccountsFixtures.user_fixture()

    {1, _} =
      from(u in User, where: u.id == ^user.id)
      |> Repo.update_all(set: [inserted_at: at(day)])

    user
  end

  defp seen(user, day), do: :ok = Analytics.record_activity(user.id, at(day))

  defp rows(user_id) do
    Repo.all(from a in ActivityDay, where: a.user_id == ^user_id, order_by: a.day, select: a.day)
  end

  describe "record_activity/2" do
    test "one row per user per UTC day, however often it is called" do
      user = AccountsFixtures.user_fixture()

      seen(user, @today)
      seen(user, @today)
      :ok = Analytics.record_activity(user.id, DateTime.new!(@today, ~T[23:59:59], "Etc/UTC"))

      assert rows(user.id) == [@today]

      seen(user, Date.add(@today, 1))
      assert rows(user.id) == [@today, Date.add(@today, 1)]
    end

    test "is a no-op for a user that does not exist" do
      assert :ok = Analytics.record_activity(Ecto.UUID.generate(), at(@today))
      assert :ok = Analytics.record_activity("not-a-uuid", at(@today))
    end

    test "a DB failure in the insert cannot fail the caller" do
      user = AccountsFixtures.user_fixture()

      # The failure seen in the wild is SQLite answering a contended write with
      # `Exqlite.Error: Database busy` under concurrent registration: it escaped
      # the old `Ecto.ConstraintError`-only rescue and 500'd
      # `POST /api/v1/login/device`. Any raise out of `Repo.insert` reaches the
      # caller the same way, and a process with no sandbox connection provokes
      # one (`DBConnection.OwnershipError`) without taking a lock on the
      # database file for the rest of the suite. A plain `spawn`, not a `Task`:
      # `$callers` would lend the child this test's connection and the insert
      # would succeed.
      test_pid = self()

      log =
        capture_log(fn ->
          spawn(fn ->
            send(test_pid, {:recorded, Analytics.record_activity(user.id, at(@today))})
          end)

          assert_receive {:recorded, :ok}, 5_000
        end)

      assert log =~ "activity day insert failed"

      # The failure left nothing cached, so the next call still records the day.
      assert rows(user.id) == []
      seen(user, @today)
      assert rows(user.id) == [@today]
    end

    test "rides along with the last_seen touches" do
      user = AccountsFixtures.user_fixture()
      today = Date.utc_today()

      :ok = Accounts.touch_last_seen(user)
      assert rows(user.id) == [today]

      :ok = Accounts.touch_last_seen_by_id(user.id)
      assert rows(user.id) == [today]
    end
  end

  describe "active users" do
    test "dau / wau / mau count distinct users in the window" do
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()
      c = AccountsFixtures.user_fixture()

      seen(a, @today)
      seen(a, Date.add(@today, -1))
      seen(b, Date.add(@today, -3))
      seen(c, Date.add(@today, -20))
      # Outside every window.
      seen(c, Date.add(@today, -40))

      assert Analytics.dau(@today) == 1
      assert Analytics.wau(@today) == 2
      assert Analytics.mau(@today) == 3
      assert Analytics.active_users(Date.add(@today, -45), Date.add(@today, -30)) == 1
    end
  end

  describe "cohorts" do
    test "daily_series reports new users, active users and strict D1/D7 per cohort" do
      cohort_day = Date.add(@today, -7)

      # Three sign-ups on cohort_day: one back the next day and on day 7, one
      # back only on day 7, one never again.
      u1 = user_registered_on(cohort_day)
      u2 = user_registered_on(cohort_day)
      _u3 = user_registered_on(cohort_day)

      Enum.each([u1, u2], &seen(&1, cohort_day))
      seen(u1, Date.add(cohort_day, 1))
      seen(u1, Date.add(cohort_day, 7))
      seen(u2, Date.add(cohort_day, 7))
      # Day 2 does not count toward D1 or D7 under the strict definition.
      seen(u2, Date.add(cohort_day, 2))

      series = Analytics.daily_series(10, @today)
      assert length(series) == 10
      assert List.first(series).day == Date.add(@today, -9)
      assert List.last(series).day == @today

      row = Enum.find(series, &(&1.day == cohort_day))
      assert row.new_users == 3
      assert row.active == 2
      assert_in_delta row.d1, 1 / 3, 1.0e-9
      assert_in_delta row.d7, 2 / 3, 1.0e-9
      # Day 30 has not happened yet.
      assert row.d30 == nil

      # A day with no sign-ups has no rate, not 0%.
      empty = Enum.find(series, &(&1.day == Date.add(@today, -3)))
      assert empty.new_users == 0
      assert empty.d1 == nil
    end

    test "summary pools D1 over cohorts old enough and skips today's cohort" do
      # Yesterday: 2 sign-ups, 1 back today → D1 50%.
      y1 = user_registered_on(Date.add(@today, -1))
      _y2 = user_registered_on(Date.add(@today, -1))
      seen(y1, @today)

      # Two days ago: 2 sign-ups, both back the next day → D1 100%.
      d1 = user_registered_on(Date.add(@today, -2))
      d2 = user_registered_on(Date.add(@today, -2))
      seen(d1, Date.add(@today, -1))
      seen(d2, Date.add(@today, -1))

      # Today: cannot have a D1 yet, must not dilute the pool.
      _t = user_registered_on(@today)

      summary = Analytics.summary(@today)
      # Pooled: (1 + 2) / (2 + 2), not the mean of 50% and 100%.
      assert_in_delta summary.d1, 0.75, 1.0e-9
      assert summary.d7 == nil
      assert summary.d30 == nil
      assert summary.new_users_7d == 5
      assert summary.new_users_30d == 5
      assert summary.dau == 1
      assert summary.mau == 3
      assert_in_delta summary.stickiness, 1 / 3, 1.0e-9
      assert summary.payers_30d == 0
      assert summary.conversion_30d == 0.0
    end

    test "summary on an empty database is all zeros and nils" do
      # Fixture users from other async tests are invisible inside the sandbox;
      # this test creates none.
      summary = Analytics.summary(~D[2000-01-01])
      assert %{dau: 0, wau: 0, mau: 0, stickiness: nil, d1: nil, d7: nil, d30: nil} = summary
    end
  end

  describe "daily counters" do
    test "count/3 increments one row per (day, key) and counts/3 reads it back" do
      day = ~D[2031-03-10]
      :ok = Analytics.count("level.finished", 1, at(day))
      :ok = Analytics.count("level.finished", 2, at(day))
      :ok = Analytics.count("level.finished", 1, at(Date.add(day, -1)))
      :ok = Analytics.count("level.failed", 1, at(day))
      :ok = Analytics.count("level.started.lang:ja", 5, at(day))

      assert Analytics.counts("level.finished", 7, day) == %{
               "level.finished" => %{day => 3, Date.add(day, -1) => 1}
             }

      # Prefix family, ordered totals.
      assert Analytics.count_totals("level.*", 7, day) == [
               {"level.started.lang:ja", 5},
               {"level.finished", 4},
               {"level.failed", 1}
             ]

      # Outside the window: nothing.
      assert Analytics.counts("level.finished", 7, Date.add(day, 30)) == %{}
    end

    test "count/3 drops bad input instead of raising" do
      assert :ok = Analytics.count("", 1, at(~D[2031-03-10]))
      assert :ok = Analytics.count(String.duplicate("k", 200), 1, at(~D[2031-03-10]))
      assert :ok = Analytics.count("x", 0, at(~D[2031-03-10]))
      assert Analytics.counts("*", 7, ~D[2031-03-10]) == %{}
    end

    test "count/3 drops a DB failure instead of raising" do
      # A counter rides along with a level end or a purchase; a contended
      # SQLite write there must not fail the write it rides on. Same setup as
      # the `record_activity/2` case above.
      test_pid = self()

      log =
        capture_log(fn ->
          spawn(fn ->
            send(test_pid, {:counted, Analytics.count("level.finished", 1, at(@today))})
          end)

          assert_receive {:counted, :ok}, 5_000
        end)

      assert log =~ "daily count level.finished failed"
    end
  end

  describe "track/3" do
    test "counts the name and each dimension, and keeps the row with its fields" do
      user = AccountsFixtures.user_fixture()

      :ok =
        Analytics.track(
          "web.game.finished",
          %{game: "hangman", lang: "ro", mode: :daily, timed: false, score: 7, total: 10},
          user_id: user.id,
          at: at(@today)
        )

      totals = "web.game.finished*" |> Analytics.count_totals(1, @today) |> Map.new()
      assert totals["web.game.finished"] == 1
      assert totals["web.game.finished.game:hangman"] == 1
      assert totals["web.game.finished.lang:ro"] == 1
      assert totals["web.game.finished.mode:daily"] == 1
      assert totals["web.game.finished.timed:false"] == 1
      # A number is a measure: in the row, never a counter.
      refute Enum.any?(totals, fn {key, _} -> String.contains?(key, "score") end)

      assert [event] = Repo.all(Event)
      assert event.name == "web.game.finished"
      assert event.user_id == user.id
      assert event.inserted_at == DateTime.truncate(at(@today), :second)

      assert event.dims == %{
               "game" => "hangman",
               "lang" => "ro",
               "mode" => "daily",
               "timed" => "false",
               "score" => 7,
               "total" => 10
             }
    end

    test "a visitor's event is counted and not kept, a nil field is dropped, a bad field is dropped with a warning" do
      log =
        capture_log(fn ->
          :ok =
            Analytics.track("web.page", %{section: "games", lang: nil, odd: [1, 2], "Bad Key": 1},
              at: at(@today)
            )
        end)

      assert log =~ "field odd = [1, 2] dropped"
      assert log =~ "field \"Bad Key\" dropped"

      assert Repo.all(Event) == []

      assert Analytics.count_totals("web.page*", 1, @today) == [
               {"web.page", 1},
               {"web.page.section:games", 1}
             ]
    end

    test "a bad name or caller is dropped with a warning, never raised" do
      log =
        capture_log(fn ->
          assert :ok = Analytics.track("Web.Game", %{}, at: at(@today))
          assert :ok = Analytics.track("web.game", %{}, user_id: 42, at: at(@today))
          assert :ok = Analytics.track("web.game", %{}, at: "yesterday")
          assert :ok = Analytics.track(:web, %{})
        end)

      assert log =~ "dropped"
      assert Repo.all(Event) == []
      assert Analytics.counts("*", 7, @today) == %{}
    end

    test "a deleted account's events stay, without the user" do
      user = AccountsFixtures.user_fixture()
      :ok = Analytics.track("web.test.finished", %{lang: "ro"}, user_id: user.id, at: at(@today))

      Repo.delete!(user)

      assert [%Event{user_id: nil, name: "web.test.finished"}] = Repo.all(Event)
    end
  end

  describe "families/3" do
    test "groups a key with its dimensions, largest first" do
      :ok = Analytics.count("level.started", 3, at(@today))
      :ok = Analytics.count("level.started.lang:ro", 2, at(@today))
      :ok = Analytics.count("level.started.lang:es", 1, at(Date.add(@today, -1)))
      :ok = Analytics.count("level.started.mode:solo", 3, at(@today))
      :ok = Analytics.count("level.failed", 1, at(@today))
      # A dimension with no bare key still makes a family.
      :ok = Analytics.count("continue.bought.attempt:1", 2, at(@today))

      # Largest total first; a family that is only dimensions has none.
      assert [started, failed, continue] = Analytics.families("*", 7, @today)

      assert started.key == "level.started"
      assert started.total == 3
      assert started.by_day == %{@today => 3}
      assert started.dims == %{"lang" => [{"ro", 2}, {"es", 1}], "mode" => [{"solo", 3}]}

      assert %{key: "level.failed", total: 1, dims: %{}} = failed
      assert %{key: "continue.bought", total: 0, dims: %{"attempt" => [{"1", 2}]}} = continue

      assert Analytics.families("level.*", 7, @today) |> Enum.map(& &1.key) ==
               ~w(level.started level.failed)
    end
  end

  describe "feature_summary/1" do
    test "distinct users per day, new to the feature, and back at the horizons" do
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()
      week_ago = Date.add(@today, -7)

      :ok = Analytics.track("web.test.finished", %{lang: "ro"}, user_id: a.id, at: at(week_ago))
      :ok = Analytics.track("web.test.finished", %{lang: "ro"}, user_id: a.id, at: at(@today))
      # Twice today is one active user.
      :ok = Analytics.track("web.test.finished", %{lang: "es"}, user_id: a.id, at: at(@today))
      :ok = Analytics.track("web.test.finished", %{lang: "ro"}, user_id: b.id, at: at(@today))
      # A visitor is counted, not kept: no row, so no feature.
      :ok = Analytics.track("web.test.finished", %{lang: "ro"}, at: at(@today))
      :ok = Analytics.track("web.page", %{section: "home"}, at: at(@today))

      assert [tests] = Analytics.feature_summary(@today)

      assert tests.name == "web.test.finished"
      assert tests.dau == 2
      assert tests.wau == 2
      assert tests.mau == 2
      assert tests.stickiness == 1.0
      # The week is today and the six days before: a's first day is out of it.
      assert tests.events_7d == 3
      assert tests.new_7d == 1
      assert tests.new_30d == 2
      # a's day 7 is today, and a is here; b has not reached any horizon.
      assert tests.d7 == 1.0
      assert tests.d1 == 0.0
      assert tests.d30 == nil
    end
  end

  describe "people_by_dimension/4" do
    test "distinct people and events per value of one dimension, largest first" do
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()

      for {user, game} <- [{a, "hangman"}, {a, "hangman"}, {b, "hangman"}, {b, "crossword"}] do
        :ok =
          Analytics.track("web.game.started", %{game: game, lang: "ro"},
            user_id: user.id,
            at: at(@today)
          )
      end

      # A round without the dimension is "none"; a visitor's is not kept.
      :ok = Analytics.track("web.game.started", %{lang: "ro"}, user_id: b.id, at: at(@today))
      :ok = Analytics.track("web.game.started", %{game: "hangman"}, at: at(@today))
      # Outside the window.
      :ok =
        Analytics.track("web.game.started", %{game: "memory"},
          user_id: a.id,
          at: at(Date.add(@today, -40))
        )

      assert Analytics.people_by_dimension("web.game.started", "game", 30, @today) == [
               %{value: "hangman", people: 2, events: 3},
               %{value: "crossword", people: 1, events: 1},
               %{value: "none", people: 1, events: 1}
             ]

      assert Analytics.people_by_dimension("web.game.started", "lang", 30, @today) == [
               %{value: "ro", people: 2, events: 5}
             ]

      assert Analytics.people_by_dimension("web.test.started", "lang", 30, @today) == []
    end
  end

  describe "recent_events/1" do
    test "newest first, as many as asked" do
      user = AccountsFixtures.user_fixture()

      for n <- 1..3 do
        :ok =
          Analytics.track("e.#{n}", %{},
            user_id: user.id,
            at: DateTime.add(at(@today), n, :minute)
          )
      end

      assert Analytics.recent_events(2) |> Enum.map(& &1.name) == ["e.3", "e.2"]
    end
  end

  describe "economy flow" do
    test "groups the ledger by day, currency and reason into granted / spent" do
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Gamend.Economy.grant(user.id, "coins", 300, reason: "treasure")
      {:ok, _} = Gamend.Economy.grant(user.id, "coins", 50, reason: "treasure")
      {:ok, _} = Gamend.Economy.spend(user.id, "coins", 100, reason: "unlock_item")
      {:ok, _} = Gamend.Economy.grant(user.id, "cups", 1, reason: "tournament_win")

      totals = Analytics.economy_totals(7)

      assert %{granted: 350, spent: 0, net: 350, entries: 2} =
               Enum.find(totals, &(&1.currency == "coins" and &1.reason == "treasure"))

      assert %{granted: 0, spent: 100, net: -100, entries: 1} =
               Enum.find(totals, &(&1.currency == "coins" and &1.reason == "unlock_item"))

      assert [%{currency: "cups", reason: "tournament_win", net: 1}] =
               Analytics.economy_totals(7, currency: "cups")

      flow = Analytics.economy_flow(7, currency: "coins")
      assert Enum.all?(flow, &(&1.day == Date.utc_today()))
      assert Enum.sum_by(flow, & &1.granted) == 350
      assert Enum.sum_by(flow, & &1.spent) == 100
    end
  end

  describe "snapshot/0" do
    test "composes every context's counters and the activity block" do
      Gamend.Cache.invalidate({:analytics, :snapshot})
      user = AccountsFixtures.user_fixture()
      seen(user, Date.utc_today())

      snapshot = Analytics.snapshot()

      assert %{players_total: total, players_online: _} = snapshot.players
      assert total >= 1
      assert snapshot.activity.dau >= 1
      assert snapshot.activity.new_users_1d >= 1
      assert Map.has_key?(snapshot.lobbies, :lobbies_total)
      assert Map.has_key?(snapshot.parties, :parties_active)
      assert Map.has_key?(snapshot.quests, :quests_total)
      assert Map.has_key?(snapshot.signaling, :rooms_active)
      assert Map.keys(snapshot.matchmaking) |> Enum.sort() == [:queued, :queues]
      assert Map.has_key?(snapshot.tournaments, :tournaments)
    end
  end
end
