defmodule GamendWeb.AdminLive.LobbiesTest do
  # This test interacts with global hooks/application state in places (eg. lobbies
  # hooks and saves). Running it concurrently can race with other tests that
  # modify the same application config, which causes flaky behaviour under CI.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  test "admin can view lobbies", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # create a few lobbies (one hosted, one hostless)
    {:ok, lobby1} =
      Gamend.Lobbies.create_lobby(%{
        title: "admin-lobby-1",
        name: "admin-lobby-1",
        host_id: user.id
      })

    {:ok, lobby2} =
      Gamend.Lobbies.create_lobby(%{
        title: "admin-lobby-2",
        name: "admin-lobby-2",
        hostless: true
      })

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/lobbies")

    assert html =~ "admin-lobby-1"
    assert html =~ "admin-lobby-2"

    # created/updated timestamps should be visible in the grid
    assert html =~ Calendar.strftime(lobby1.inserted_at, "%Y-%m-%d %H:%M")
    assert html =~ Calendar.strftime(lobby1.updated_at, "%Y-%m-%d %H:%M")

    # ensure back to admin link exists
    assert html =~ "← Back to Admin"

    # test edit flow via live view: open manage UI, change title and save
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/admin/lobbies")

    # open edit modal for first lobby (its row) and verify modal shows created/updated
    view |> element("#admin-lobby-#{lobby1.id}") |> render_click()

    modal_html = render(view)
    assert modal_html =~ "Created:"
    assert modal_html =~ Calendar.strftime(lobby1.inserted_at, "%Y-%m-%d %H:%M:%S")
    assert modal_html =~ "Updated:"
    assert modal_html =~ Calendar.strftime(lobby1.updated_at, "%Y-%m-%d %H:%M:%S")

    # submit save with new title
    form = form(view, "#lobby-form", %{"lobby" => %{"title" => "Updated Title"}})
    render_submit(form)

    # ensure update is persisted
    assert Gamend.Lobbies.get_lobby!(lobby1.id).title == "Updated Title"

    # now delete second lobby
    delete_btn = element(view, "#admin-lobby-#{lobby2.id} button", "Delete")
    render_click(delete_btn)

    # re-fetch the page and ensure that the specific lobby element is gone
    _html2 = render(view)
    refute has_element?(view, "#admin-lobby-#{lobby2.id}")
  end

  test "admin lobbies pagination displays totals and disables Next on last page", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # create 30 lobbies so admin listing has two pages with default page_size 25
    for i <- 1..30 do
      Gamend.Lobbies.create_lobby(%{
        name: "admin-pagi-#{i}",
        title: "Admin Pagi #{i}",
        hostless: true
      })
    end

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin/lobbies")

    assert html =~ "(30)"
    assert html =~ "/ 2"

    # Next enabled on first page (no disabled attr on admin_lobbies_next)
    assert html =~ ~s(phx-click="admin_lobbies_next")
    refute html =~ ~r/<button[^>]*phx-click="admin_lobbies_next"[^>]*disabled/

    # go to next page
    view |> element(~S(button[phx-click="admin_lobbies_next"])) |> render_click()
    html2 = render(view)

    # on last page Next should be disabled
    assert html2 =~ ~r/<button[^>]*phx-click="admin_lobbies_next"[^>]*disabled/
  end

  test "admin update is reflected in admin lobbies view", %{conn: conn} do
    user = Gamend.AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Gamend.Repo.update()

    # create a lobby hosted by admin
    {:ok, lobby} =
      Gamend.Lobbies.create_lobby(%{
        title: "admin-prop",
        name: "admin-prop",
        host_id: admin.id
      })

    # admin opens admin page and edits the lobby title
    {:ok, view_admin, _html} = conn |> log_in_user(admin) |> live(~p"/admin/lobbies")
    assert render(view_admin) =~ "admin-prop"

    view_admin |> element("#admin-lobby-#{lobby.id}") |> render_click()
    form = form(view_admin, "#lobby-form", %{"lobby" => %{"title" => "Admin Updated"}})
    render_submit(form)

    updated_html = render(view_admin)
    assert updated_html =~ "Admin Updated"
  end

  test "admin creates a lobby with a host id submitted as form text", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    host = AccountsFixtures.user_fixture()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/lobbies")

    view |> element(~S(button[phx-click="show_create"])) |> render_click()

    view
    |> form("#lobby-create-form", %{
      "lobby" => %{"title" => "form-created-lobby", "max_users" => "8", "host_id" => host.id}
    })
    |> render_submit()

    lobby = Repo.get_by(Gamend.Lobbies.Lobby, title: "form-created-lobby")
    assert lobby
    assert lobby.host_id == host.id
    assert lobby.max_users == 8
  end

  test "admin adds a lobby member by user id and rejects non-UUID input", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    member = AccountsFixtures.user_fixture()

    {:ok, lobby} =
      Gamend.Lobbies.create_lobby(%{
        title: "members-lobby",
        name: "members-lobby",
        hostless: true
      })

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/lobbies")

    render_click(view, "view_members", %{"id" => lobby.id})
    render_click(view, "update_add_member_id", %{"value" => member.id})
    render_click(view, "add_member", %{})

    members = Gamend.Lobbies.list_memberships_for_lobby(lobby.id)
    assert Enum.any?(members, &(&1.id == member.id))

    # garbage input must not add anyone (and must not crash the LiveView)
    render_click(view, "update_add_member_id", %{"value" => "12345"})
    render_click(view, "add_member", %{})

    assert length(Gamend.Lobbies.list_memberships_for_lobby(lobby.id)) == length(members)
  end

  test "admin deletion removes the lobby from admin lobbies view", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # create a lobby
    {:ok, lobby} =
      Gamend.Lobbies.create_lobby(%{
        title: "cross-delete",
        name: "cross-delete",
        host_id: admin.id
      })

    # admin opens admin page and deletes the lobby
    {:ok, view_admin, _html} = conn |> log_in_user(admin) |> live(~p"/admin/lobbies")
    assert render(view_admin) =~ "cross-delete"

    delete_btn = element(view_admin, "#admin-lobby-#{lobby.id} button", "Delete")
    render_click(delete_btn)

    updated_html = render(view_admin)
    refute updated_html =~ "cross-delete"
  end
end
