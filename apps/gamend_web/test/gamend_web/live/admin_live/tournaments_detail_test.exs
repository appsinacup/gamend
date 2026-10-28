defmodule GamendWeb.AdminLive.TournamentsDetailTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Tournaments

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true, display_name: "Boss Admin"})
    %{conn: log_in_user(conn, admin)}
  end

  defp tournament_with(n) do
    {:ok, t} =
      Tournaments.create_tournament(%{
        slug: "admin-cup-#{System.unique_integer([:positive])}",
        title: "Admin Cup",
        starts_at: DateTime.add(DateTime.utc_now(:second), 3600),
        round_window_sec: 600,
        bracket_size: 4
      })

    for i <- 1..n do
      u = AccountsFixtures.user_fixture()
      {:ok, u} = Accounts.update_user(u, %{display_name: "Player #{i}"})
      {:ok, _} = Tournaments.join_tournament(u, Tournaments.advance_lifecycle(t))
    end

    t
  end

  test "detail shows player names, not raw ids", %{conn: conn} do
    t = tournament_with(3)
    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view |> element("tr[phx-click='open_detail'][phx-value-id='#{t.id}']") |> render_click()

    assert html =~ "Player 1"
    assert html =~ "Entries (3)"
  end

  test "entries paginate beyond one page", %{conn: conn} do
    t = tournament_with(27)
    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view |> element("tr[phx-click='open_detail'][phx-value-id='#{t.id}']") |> render_click()

    assert html =~ "Entries (27)"
    assert html =~ "1 / 2 (27)"

    html = view |> element("button[phx-click='detail_next']") |> render_click()
    assert html =~ "2 / 2 (27)"
  end

  test "matches are shown per bracket with a picker and tree link", %{conn: conn} do
    t = tournament_with(4)
    {:ok, t} = Tournaments.update_tournament(t, %{starts_at: DateTime.utc_now(:second)})
    t = Tournaments.advance_lifecycle(t)
    assert t.state == "running"

    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view |> element("tr[phx-click='open_detail'][phx-value-id='#{t.id}']") |> render_click()

    assert html =~ "Matches — bracket 1"
    assert html =~ "View bracket tree"
    assert html =~ ~p"/tournaments/#{t.id}/brackets/0"
    # names, not uuids, in match rows
    assert html =~ "Player "
  end
end
