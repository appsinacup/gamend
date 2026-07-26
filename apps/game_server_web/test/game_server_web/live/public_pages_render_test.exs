defmodule GameServerWeb.PublicPagesRenderTest do
  @moduledoc """
  Basic render tests for public LiveView pages (live_session :current_user).
  These catch crashes like missing assigns or template errors.
  """
  use GameServerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "unauthenticated" do
    test "GET /leaderboards renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/leaderboards")
      assert html =~ "Leaderboards"
    end

    test "GET /quests renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/quests")
      assert html =~ "Quests"
    end

    test "GET /groups renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/groups")
      assert html =~ "Groups"
    end

    test "GET /roadmap renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/roadmap")
      assert html =~ "Roadmap"
    end

    test "GET /changelog renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/changelog")
      assert html =~ "Changelog"
    end

    test "GET /blog renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/blog")
      assert html =~ "Blog"
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "GET /leaderboards renders when logged in", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/leaderboards")
      assert html =~ "Leaderboards"
    end

    test "GET /quests renders when logged in", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/quests")
      assert html =~ "Quests"
    end

    # An empty page renders even when the card markup is broken, so seed one
    # quest of every shape and actually render the cards.
    test "GET /quests renders a card of every quest shape", %{conn: conn} do
      now = DateTime.utc_now(:second)

      {:ok, _} =
        GameServer.Quests.create_quest(%{
          key: "render_daily",
          title: "Daily",
          category: "daily",
          reset: "daily",
          objectives: [%{event: "e", target: 3}],
          rewards: [%{type: "currency", code: "gold", amount: 10}]
        })

      {:ok, _} =
        GameServer.Quests.create_quest(%{
          key: "render_interval",
          title: "Biweekly",
          reset: "interval",
          reset_interval_days: 14,
          objectives: [%{event: "e", target: 1}]
        })

      {:ok, _} =
        GameServer.Quests.create_quest(%{
          key: "render_event",
          title: "Seasonal",
          category: "seasonal",
          reset: "weekly",
          starts_at: DateTime.add(now, -3600),
          ends_at: DateTime.add(now, 3600),
          objectives: [%{event: "e", target: 1}]
        })

      {:ok, _} =
        GameServer.Quests.create_quest(%{
          key: "render_chain",
          title: "Chained",
          reset: "never",
          prerequisite_quest_key: "render_daily",
          objectives: [%{event: "e", target: 1}]
        })

      {:ok, _} =
        GameServer.Quests.create_quest(%{
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

    test "GET /groups renders when logged in", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/groups")
      assert html =~ "Groups"
    end

    test "clicking a chained quest opens the chain with locked tiers ahead", %{
      conn: conn,
      user: user
    } do
      {:ok, _} =
        GameServer.Quests.create_quest(%{
          key: "chain_t1",
          title: "First step",
          reset: "never",
          objectives: [%{event: "chain_e", target: 1}]
        })

      {:ok, _} =
        GameServer.Quests.create_quest(%{
          key: "chain_t2",
          title: "Second step",
          reset: "never",
          prerequisite_quest_key: "chain_t1",
          objectives: [%{event: "chain_e", target: 1}]
        })

      {:ok, _} =
        GameServer.Quests.create_quest(%{
          key: "chain_t3",
          title: "Final step",
          reset: "never",
          prerequisite_quest_key: "chain_t2",
          objectives: [%{event: "chain_e", target: 1}]
        })

      {:ok, _} = GameServer.Quests.report_event(user.id, "chain_e")

      {:ok, view, html} = live(conn, ~p"/quests")

      # Tier 3 is hidden from the list until tier 2 completes...
      refute html =~ "Final step"

      # ...but the chain view shows the whole line, locked tiers included.
      html = render_click(view, "show_chain", %{"key" => "chain_t2"})
      assert html =~ "Quest chain"
      assert html =~ "First step"
      assert html =~ "Second step"
      assert html =~ "Final step"
      assert html =~ "Locked"

      html = render_click(view, "close_chain", %{})
      refute html =~ "Quest chain"
    end
  end
end
