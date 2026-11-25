defmodule GamendWeb.PublicPagesRenderTest do
  @moduledoc """
  Basic render tests for public LiveView pages (live_session :current_user).
  These catch crashes like missing assigns or template errors.
  """
  # One group with every other async module that makes a quest: making one
  # takes the quest definitions' Postgres lock, held to the end of the test's
  # sandbox transaction, so two such modules at once wait on each other past
  # the 15 s DB timeout (CI, 2026-11-25). The group runs them one at a time.
  use GamendWeb.ConnCase, async: true, group: :quest_definitions
  import Phoenix.LiveViewTest

  @pages ~w(/leaderboards /quests /groups /roadmap /changelog /blog)

  describe "unauthenticated" do
    for path <- @pages do
      test "GET #{path} renders", %{conn: conn} do
        assert {:ok, _view, _html} = live(conn, unquote(path))
      end
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    # /quests is rendered, with a card of every shape, below.
    for path <- ~w(/leaderboards /groups) do
      test "GET #{path} renders when logged in", %{conn: conn} do
        assert {:ok, _view, _html} = live(conn, unquote(path))
      end
    end

    # An empty page renders even when the card markup is broken, so seed one
    # quest of every shape and actually render the cards.
    test "GET /quests renders a card of every quest shape", %{conn: conn} do
      now = DateTime.utc_now(:second)

      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "render_daily",
          title: "Daily",
          category: "daily",
          reset: "daily",
          objectives: [%{event: "e", target: 3}],
          rewards: [%{type: "currency", code: "gold", amount: 10}]
        })

      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "render_interval",
          title: "Biweekly",
          reset: "interval",
          reset_interval_days: 14,
          objectives: [%{event: "e", target: 1}]
        })

      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "render_event",
          title: "Seasonal",
          category: "seasonal",
          reset: "weekly",
          starts_at: DateTime.add(now, -3600),
          ends_at: DateTime.add(now, 3600),
          objectives: [%{event: "e", target: 1}]
        })

      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "render_chain",
          title: "Chained",
          reset: "never",
          prerequisite_quest_key: "render_daily",
          objectives: [%{event: "e", target: 1}]
        })

      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "render_secret",
          title: "Secret",
          hidden: true,
          reset: "never",
          objectives: [%{event: "e", target: 1}]
        })

      {:ok, _view, html} = live(conn, ~p"/quests")

      assert html =~ "Daily"
      assert html =~ "Biweekly"
      assert html =~ "Seasonal"
      # Hidden quests are teased, never revealed.
      assert html =~ "???"
      refute html =~ "Secret"
      # Chained quests stay out of sight until their prerequisite is done.
      refute html =~ "Chained"
    end

    test "a chained quest is the tier the player is on: no number, no tiers ahead", %{
      conn: conn,
      user: user
    } do
      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "chain_t1",
          title: "First step",
          reset: "never",
          objectives: [%{event: "chain_e", target: 1}]
        })

      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "chain_t2",
          title: "Second step",
          reset: "never",
          prerequisite_quest_key: "chain_t1",
          objectives: [%{event: "chain_e", target: 1}]
        })

      {:ok, _} =
        Gamend.Quests.create_quest(%{
          key: "chain_t3",
          title: "Final step",
          reset: "never",
          prerequisite_quest_key: "chain_t2",
          objectives: [%{event: "chain_e", target: 1}]
        })

      {:ok, _} = Gamend.Quests.report_event(user.id, "chain_e")

      {:ok, view, html} = live(conn, ~p"/quests")

      # Tier 3 is hidden until tier 2 completes, and nothing numbers the
      # tiers or opens the ones ahead (user, 2026-10-27).
      refute html =~ "Final step"
      refute html =~ ~r{\b\d+/3\b}
      refute has_element?(view, ~s([phx-click="show_chain"]))
    end
  end
end
