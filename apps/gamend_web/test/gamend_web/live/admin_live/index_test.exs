defmodule GamendWeb.AdminLive.IndexTest do
  use GamendWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.KV
  alias Gamend.Repo
  alias GamendWeb.AdminLive.Pages
  alias GamendWeb.Gettext.Stats

  defp card(path), do: ~s|#admin-cards .card:has(a[href="#{path}"])|

  test "every page in the table opens from a card on the dashboard", %{conn: conn} do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    for %{path: path} <- Pages.dashboard() do
      assert has_element?(view, card(path)), "no card opens #{path}"
    end
  end

  test "the dashboard is cards alone, with no menu and no View link", %{conn: conn} do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(view, "#admin-cards")
    refute has_element?(view, "#admin-menu")
    refute html =~ "View →"
  end

  test "the translations card lists three languages and counts the rest", %{conn: conn} do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    hidden = length(Stats.all_completeness()) - 3

    assert hidden > 0
    assert has_element?(view, card("/admin/translations"), "+#{hidden} more")
  end

  test "admin dashboard shows lobbies count on its card", %{conn: conn} do
    admin = AccountsFixtures.user_fixture()

    {:ok, admin} =
      admin
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # create two lobbies so count will be 2
    Gamend.Lobbies.create_lobby(%{title: "dash-1", hostless: true})
    Gamend.Lobbies.create_lobby(%{title: "dash-2", hostless: true})

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(view, card("/admin/lobbies"), ~r/Lobbies\s+2\s+Hostless/)
  end

  test "admin overview shows user/provider and leaderboard stats", %{conn: conn} do
    admin = AccountsFixtures.user_fixture()

    {:ok, admin} =
      admin
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # create users with providers and passwords
    u1 = AccountsFixtures.user_fixture()
    u2 = AccountsFixtures.user_fixture()

    Repo.update!(Ecto.Changeset.change(u1, %{google_id: "g-1"}))
    Repo.update!(Ecto.Changeset.change(u2, %{discord_id: "d-1"}))

    # give u2 a password
    AccountsFixtures.set_password(u2)

    # create leaderboard and submit two scores
    {:ok, lb} =
      Gamend.Leaderboards.create_leaderboard(%{
        slug: "admin_stats",
        title: "Admin Stats",
        sort_order: :desc,
        operator: :incr
      })

    {:ok, _} = Gamend.Leaderboards.submit_score(lb.id, u1.id, 10)
    {:ok, _} = Gamend.Leaderboards.submit_score(lb.id, u2.id, 20)

    {:ok, _view, html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert html =~ "Users"
    assert html =~ "Google: 1"
    assert html =~ "Discord: 1"
    assert html =~ "With password: 1"
    assert html =~ "Leaderboards"
    assert html =~ "Scores total: 2"
  end

  test "admin dashboard shows kv count on its card", %{conn: conn} do
    admin = AccountsFixtures.user_fixture()

    {:ok, admin} =
      admin
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    {:ok, _} = KV.put("dash-kv-1", %{v: 1}, %{"m" => "a"})
    {:ok, _} = KV.put("dash-kv-2", %{v: 2}, %{"m" => "b"})

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(view, card("/admin/kv"), ~r/Key-Value\s+2\s+Global/)
  end
end
