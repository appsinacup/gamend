defmodule GamendWeb.AdminLive.AnalyticsTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Analytics
  alias Gamend.Repo

  defp admin_conn(conn) do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    log_in_user(conn, admin)
  end

  test "the overview: summary tiles, charts and the per-day table", %{conn: conn} do
    conn = admin_conn(conn)
    user = AccountsFixtures.user_fixture()
    :ok = Analytics.record_activity(user.id, DateTime.utc_now())

    {:ok, lv, html} = live(conn, ~p"/admin/analytics")

    assert html =~ "Analytics"
    assert html =~ "DAU"
    assert html =~ "D30"
    assert html =~ ~s(id="chart-active")
    assert html =~ Date.to_iso8601(Date.utc_today())
    # Nothing has reached a D7 yet: rendered as a dash, never as 0%.
    assert html =~ "—"

    html = lv |> element("a", "90 days") |> render_click()
    assert_patch(lv, ~p"/admin/analytics?days=90")
    assert length(Regex.scan(~r/<td class="font-mono">/, html)) == 90
  end

  test "features, counters and the rows of an event", %{conn: conn} do
    conn = admin_conn(conn)
    user = AccountsFixtures.user_fixture()

    :ok =
      Analytics.track("web.game.finished", %{game: "hangman", lang: "ro", score: 7},
        user_id: user.id
      )

    {:ok, _lv, html} = live(conn, ~p"/admin/analytics/features")
    assert html =~ "web.game.finished"

    {:ok, lv, html} = live(conn, ~p"/admin/analytics/counters")
    assert html =~ "web.game.finished"
    assert html =~ "hangman"

    lv |> element("a", "30 days") |> render_click()
    assert_patch(lv, ~p"/admin/analytics/counters?days=30")

    {:ok, _lv, html} = live(conn, ~p"/admin/analytics/explore?event=web.game.finished")
    assert html =~ "score=7"
    assert html =~ String.slice(user.id, 0, 8)
  end

  test "an event broken down by one of its dimensions: people per value", %{conn: conn} do
    conn = admin_conn(conn)
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    for {user, game} <- [{a, "hangman"}, {b, "hangman"}, {b, "crossword"}] do
      :ok = Analytics.track("web.game.started", %{game: game, lang: "ro"}, user_id: user.id)
    end

    {:ok, lv, _html} = live(conn, ~p"/admin/analytics/explore?event=web.game.started&by=game")

    # hangman: two people, one round each; crossword below it.
    assert lv |> element("#explore-breakdown") |> render() =~
             ~r/hangman.*>2<.*>2<.*crossword.*>1<.*>1</s

    {:ok, lv, _html} = live(conn, ~p"/admin/analytics/explore?event=web.game.started&by=lang")
    assert lv |> element("#explore-breakdown") |> render() =~ ~r/>\s*ro\s*<.*>2<.*>3</s

    # One account: its page, and Explore narrowed to it.
    {:ok, _lv, html} = live(conn, ~p"/admin/analytics/people?user=#{a.id}")
    assert html =~ "web.game.started"
    assert html =~ a.id
  end
end
