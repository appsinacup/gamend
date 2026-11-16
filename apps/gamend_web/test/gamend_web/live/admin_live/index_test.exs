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

  defp admin_dashboard(conn) do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")
    {view, render_async(view, 30_000)}
  end

  defp has?(doc, selector), do: not Enum.empty?(LazyHTML.query(doc, selector))

  # One mount, parsed once, for what the dashboard is made of (`has_element?/2`
  # would render and parse the page again for each of its ~40 cards); each
  # check names what failed.
  test "cards alone, in named sections of four or more, one opening every page", %{conn: conn} do
    {_view, html} = admin_dashboard(conn)

    doc = LazyHTML.from_fragment(html)
    names = doc |> LazyHTML.query("#admin-cards > section > h2") |> Enum.map(&LazyHTML.text/1)

    assert names == ~w(Players Gameplay Social Moderation Data Configuration Server)

    for {name, nth} <- Enum.with_index(names, 1) do
      cards = LazyHTML.query(doc, "#admin-cards > section:nth-child(#{nth}) .card")

      assert Enum.count(cards) >= 4, "#{name} has fewer than four cards"
    end

    for %{path: path} <- Pages.dashboard() do
      assert has?(doc, card(path)), "no card opens #{path}"
    end

    refute has?(doc, "#admin-menu")

    # The translations card lists three languages and counts the rest.
    hidden = length(Stats.all_completeness()) - 3

    assert hidden > 0

    assert doc |> LazyHTML.query(card("/admin/translations")) |> LazyHTML.text() =~
             "+#{hidden} more"
  end

  # The counts are read once the socket is up: the first render says so.
  test "the figures arrive after the page", %{conn: conn} do
    Gamend.Cache.invalidate({:admin_dashboard_stats})
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert html =~ "admin-cards-loading"
    render_async(view, 30_000)
    assert has_element?(view, "#admin-cards")
    refute has_element?(view, "#admin-cards-loading")
  end

  test "the cards count lobbies, players by provider, scores and keys", %{conn: conn} do
    Gamend.Lobbies.create_lobby(%{title: "dash-1", hostless: true})
    Gamend.Lobbies.create_lobby(%{title: "dash-2", hostless: true})

    # One player signed in with Google, one with Discord and a password.
    u1 = AccountsFixtures.user_fixture()
    u2 = AccountsFixtures.user_fixture()
    Repo.update!(Ecto.Changeset.change(u1, %{google_id: "g-1"}))
    Repo.update!(Ecto.Changeset.change(u2, %{discord_id: "d-1"}))
    AccountsFixtures.set_password(u2)

    {:ok, lb} =
      Gamend.Leaderboards.create_leaderboard(%{
        slug: "admin_stats",
        title: "Admin Stats",
        sort_order: :desc,
        operator: :incr
      })

    {:ok, _} = Gamend.Leaderboards.submit_score(lb.id, u1.id, 10)
    {:ok, _} = Gamend.Leaderboards.submit_score(lb.id, u2.id, 20)

    {:ok, _} = KV.put("dash-kv-1", %{v: 1}, %{"m" => "a"})
    {:ok, _} = KV.put("dash-kv-2", %{v: 2}, %{"m" => "b"})

    {view, html} = admin_dashboard(conn)

    assert has_element?(view, card("/admin/lobbies"), ~r/Lobbies\s+2\s+Hostless/)
    assert html =~ "Google: 1"
    assert html =~ "Discord: 1"
    assert html =~ "With password: 1"
    assert html =~ "Scores total: 2"
    assert has_element?(view, card("/admin/kv"), ~r/Key-Value\s+2\s+Global/)
  end
end
