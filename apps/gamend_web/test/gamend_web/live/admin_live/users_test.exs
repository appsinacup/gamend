defmodule GamendWeb.AdminLive.UsersTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  test "admin users pagination displays totals and disables Next on last page", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # create 30 users so admin listing has two pages with default page_size 25
    for i <- 1..30 do
      AccountsFixtures.user_fixture(%{email: "pagi-user-#{i}@example.com"})
    end

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin/users")

    # total count visible
    assert html =~ "(30)" or html =~ "(31)"

    # page total should show at least "/ 2"
    assert html =~ "/ 2"

    # Next enabled on first page
    assert html =~ ~s(phx-click="admin_users_next")
    refute html =~ ~r/<button[^>]*phx-click="admin_users_next"[^>]*disabled/

    # go to next page
    view |> element(~S(button[phx-click="admin_users_next"])) |> render_click()
    html2 = render(view)

    # on last page Next should be disabled
    assert html2 =~ ~r/<button[^>]*phx-click="admin_users_next"[^>]*disabled/
  end

  test "filter by provider checkboxes works and updates counts", %{conn: conn} do
    # admin user
    user = AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # create users with provider fields using provider helpers
    {:ok, _d1} =
      Accounts.find_or_create_from_discord(%{
        discord_id: "d1",
        email: "discord1@example.com"
      })

    {:ok, _d2} =
      Accounts.find_or_create_from_discord(%{
        discord_id: "d2",
        email: "discord2@example.com"
      })

    {:ok, _g1} =
      Accounts.find_or_create_from_google(%{
        google_id: "g1",
        email: "google1@example.com"
      })

    {:ok, _s1} =
      Accounts.find_or_create_from_steam(%{
        steam_id: "s1"
      })

    _plain = AccountsFixtures.user_fixture(%{email: "plain@example.com"})
    # create a user with a password so they show up in the email/password filter
    _password_user =
      AccountsFixtures.user_fixture(%{email: "pw@example.com"})
      |> AccountsFixtures.set_password()

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin/users")

    # verify all users present initially
    assert html =~ "discord1@example.com"
    assert html =~ "discord2@example.com"
    assert html =~ "google1@example.com"
    assert html =~ "s1"
    assert html =~ "plain@example.com"

    # toggle discord filter on
    view
    |> element(~S(input[phx-click="toggle_provider"][phx-value-provider="discord"]))
    |> render_click(%{"provider" => "discord"})

    html2 = render(view)

    # only discord users should remain
    assert html2 =~ "discord1@example.com"
    assert html2 =~ "discord2@example.com"
    refute html2 =~ "google1@example.com"
    refute html2 =~ "plain@example.com"

    # heading count should reflect 2 users (may include other system users depending on fixtures)
    assert html2 =~ "(2)" or html2 =~ "(3)"

    # toggle discord off and google on
    view
    |> element(~S(input[phx-click="toggle_provider"][phx-value-provider="discord"]))
    |> render_click(%{"provider" => "discord"})

    view
    |> element(~S(input[phx-click="toggle_provider"][phx-value-provider="google"]))
    |> render_click(%{"provider" => "google"})

    html3 = render(view)

    assert html3 =~ "google1@example.com"
    refute html3 =~ "discord1@example.com"
    refute html3 =~ "discord2@example.com"

    # now test email/password filter
    view
    |> element(~S(input[phx-click="toggle_provider"][phx-value-provider="google"]))
    |> render_click(%{"provider" => "google"})

    # toggle on email filter
    view
    |> element(~S(input[phx-click="toggle_provider"][phx-value-provider="email"]))
    |> render_click(%{"provider" => "email"})

    html4 = render(view)

    assert html4 =~ "pw@example.com"
    # toggle steam filter on
    view
    |> element(~S(input[phx-click="toggle_provider"][phx-value-provider="steam"]))
    |> render_click(%{"provider" => "steam"})

    html5 = render(view)

    assert html5 =~ "s1"
    refute html5 =~ "discord1@example.com"
    refute html5 =~ "google1@example.com"
    refute html4 =~ "discord1@example.com"
    refute html4 =~ "google1@example.com"
  end

  test "search by various IDs works", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, admin} = user |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    # Create users with specific IDs
    {:ok, _u1} =
      Accounts.find_or_create_from_discord(%{discord_id: "discord-123", email: "d@ex.com"})

    {:ok, _u2} =
      Accounts.find_or_create_from_google(%{google_id: "google-456", email: "g@ex.com"})

    {:ok, _u3} = Accounts.find_or_create_from_device("device-789")

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/users")

    # Search by Discord ID
    html = view |> form("#admin-user-search-form", %{q: "discord-123"}) |> render_change()
    assert html =~ "d@ex.com"
    refute html =~ "g@ex.com"

    # Search by Google ID
    html = view |> form("#admin-user-search-form", %{q: "google-456"}) |> render_change()
    assert html =~ "g@ex.com"
    refute html =~ "d@ex.com"

    # Search by Device ID
    html = view |> form("#admin-user-search-form", %{q: "device-789"}) |> render_change()
    assert html =~ "Users (1)"

    # Search by huge numeric ID (should not crash)
    huge_id = "114490045942966566293"
    html = view |> form("#admin-user-search-form", %{q: huge_id}) |> render_change()

    # Should not crash, and should return 0 results (unless we had a user with that google_id, but we don't here)
    assert html =~ "Users (0)"
  end

  test "the unverified filter shows only emails nobody confirmed", %{conn: conn} do
    {:ok, admin} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    _verified = AccountsFixtures.user_fixture(%{email: "verified@example.com"})
    _pending = AccountsFixtures.unconfirmed_user_fixture(%{email: "pending@example.com"})

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/users")

    html =
      view
      |> element(~S(input[phx-click="toggle_provider"][phx-value-provider="unverified"]))
      |> render_click(%{"provider" => "unverified"})

    assert html =~ "pending@example.com"
    refute html =~ "verified@example.com"
  end

  test "?filter=unverified starts with the filter on", %{conn: conn} do
    {:ok, admin} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    _verified = AccountsFixtures.user_fixture(%{email: "verified@example.com"})
    _pending = AccountsFixtures.unconfirmed_user_fixture(%{email: "pending@example.com"})

    {:ok, _view, html} = conn |> log_in_user(admin) |> live(~p"/admin/users?filter=unverified")

    assert html =~ "pending@example.com"
    refute html =~ "verified@example.com"
  end
end
