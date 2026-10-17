defmodule GamendWeb.LobbyLive.IndexTest do
  # The live lobbies page (`/admin/lobbies/live`): a lobby created from the
  # form (once: a player already in one is refused), an open lobby joined, a
  # locked one refused, a password one asking for its password (wrong, then
  # right), a lobby managed by its host (an unreadable size left alone) and
  # viewed by anyone else, a member kicked, the lobby left, the pager, and
  # the lobby events that redraw it.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Repo

  # The page is an admin's (`require_admin`), so every player on it is one.
  defp admin! do
    user = AccountsFixtures.user_fixture()
    {:ok, user} = user |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    user
  end

  setup do
    %{admin: admin!()}
  end

  defp page(conn, user, path \\ ~p"/admin/lobbies/live") do
    {:ok, view, _html} = conn |> log_in_user(user) |> live(path)
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns
  defp flash(view, key), do: Phoenix.Flash.get(assigns(view).flash, key)
  defp lobby_of(user), do: Gamend.Accounts.get_user(user.id).lobby_id

  defp hosted(attrs \\ %{}) do
    host = admin!()

    {:ok, lobby} =
      Lobbies.create_lobby(Map.merge(%{"title" => "room", "host_id" => host.id}, attrs))

    {host, lobby}
  end

  test "a lobby is created from the form, and only one", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    view |> form("#lobby-create-form", %{"title" => "Crew"}) |> render_change()
    assert assigns(view).title == "Crew"

    view |> form("#lobby-create-form", %{"title" => "Crew"}) |> render_submit()
    lobby_id = lobby_of(admin)
    assert lobby_id
    assert has_element?(view, "#lobby-#{lobby_id}")
    assert assigns(view).title == ""

    view |> form("#lobby-create-form", %{"title" => "Second"}) |> render_submit()
    assert flash(view, :error) =~ "Failed"
    assert lobby_of(admin) == lobby_id
  end

  test "an open lobby is joined; one already joined says so", %{conn: conn, admin: admin} do
    {_host, lobby} = hosted()
    view = page(conn, admin)

    render_click(view, "start_join", %{"id" => lobby.id})
    assert lobby_of(admin) == lobby.id

    render_click(view, "join_lobby", %{"id" => lobby.id})
    assert flash(view, :info) =~ "Joined"
  end

  test "a locked lobby is refused, an unknown one is not found", %{conn: conn, admin: admin} do
    {_host, locked} = hosted(%{"is_locked" => true})
    view = page(conn, admin)

    render_click(view, "start_join", %{"id" => locked.id})
    assert lobby_of(admin) == nil

    render_click(view, "start_join", %{"id" => "not-an-id"})
    assert flash(view, :error) =~ "Not found"
    render_click(view, "start_join", %{"id" => Ecto.UUID.generate()})
    render_click(view, "join_lobby", %{"id" => Ecto.UUID.generate()})
    assert flash(view, :error) =~ "Not found"
  end

  test "a password lobby asks for its password: wrong, then right", %{conn: conn, admin: admin} do
    {_host, lobby} = hosted(%{"password" => "secret"})
    view = page(conn, admin)

    render_click(view, "start_join", %{"id" => lobby.id})
    assert assigns(view).joining_lobby_id == lobby.id
    assert_patch(view, ~p"/admin/lobbies/live?join=#{lobby.id}")

    form = form(view, "#lobby-join-#{lobby.id}", %{"password" => "nope"})
    render_change(form)
    assert assigns(view).join_password == "nope"
    render_submit(form)
    assert lobby_of(admin) == nil
    assert flash(view, :error) == "Wrong password."

    view |> form("#lobby-join-#{lobby.id}", %{"password" => "secret"}) |> render_submit()
    assert lobby_of(admin) == lobby.id

    render_click(view, "join_lobby", %{"id" => lobby.id})
    render_click(view, "cancel_join", %{})
    assert assigns(view).joining_lobby_id == nil
  end

  test "the join form comes back from the URL after a reload", %{conn: conn, admin: admin} do
    {_host, lobby} = hosted(%{"password" => "secret"})
    view = page(conn, admin, ~p"/admin/lobbies/live?join=#{lobby.id}")
    assert has_element?(view, "#lobby-join-#{lobby.id}")
  end

  test "the host manages the lobby; an unreadable size is left alone", %{conn: conn} do
    {host, lobby} = hosted(%{"max_users" => 4})
    view = page(conn, host)

    render_click(view, "start_manage", %{"id" => lobby.id})
    assert assigns(view).editing_can_edit

    view
    |> form("#lobby-manage-#{lobby.id}", %{"title" => "Renamed", "max_users" => "6"})
    |> render_change()

    assert assigns(view).edit_attrs["title"] == "Renamed"

    render_submit(view, "update_lobby", %{
      "_id" => lobby.id,
      "title" => "Renamed",
      "max_users" => "six",
      "is_hidden" => "true",
      "password" => "pw"
    })

    updated = Lobbies.get_lobby(lobby.id)
    assert updated.title == "Renamed"
    assert updated.max_users == 4
    assert updated.is_hidden
    assert updated.password_hash
    assert flash(view, :info) =~ "Success."

    # A change for a form that is not the open one is ignored.
    render_change(view, "manage_change", %{"_id" => Ecto.UUID.generate(), "title" => "x"})
    assert assigns(view).edit_attrs["title"] == "Renamed"

    render_click(view, "cancel_manage", %{})
    assert assigns(view).editing_lobby_id == nil
  end

  test "anyone else sees the lobby read-only and cannot change it", %{conn: conn} do
    {_host, lobby} = hosted()
    view = page(conn, admin!())

    render_click(view, "start_manage", %{"id" => lobby.id})
    refute assigns(view).editing_can_edit

    render_submit(view, "update_lobby", %{"_id" => lobby.id, "title" => "Mine now"})
    assert Lobbies.get_lobby(lobby.id).title == "room"
    assert flash(view, :error) == "Only the host can do that."
  end

  test "the host kicks a member, who is told; then leaves", %{conn: conn} do
    {host, lobby} = hosted(%{"max_users" => 4})
    member = AccountsFixtures.user_fixture()
    {:ok, _} = Lobbies.join_lobby(member, lobby.id)
    view = page(conn, host)

    render_click(view, "kick", %{"lobby_id" => lobby.id, "target_id" => member.id})
    assert lobby_of(member) == nil

    render_click(view, "kick", %{"lobby_id" => lobby.id, "target_id" => Ecto.UUID.generate()})
    assert flash(view, :error)

    render_click(view, "leave", %{})
    assert lobby_of(host) == nil

    render_click(view, "leave", %{})
    assert flash(view, :error) == "You are not in this lobby."
  end

  test "a kicked player's own page says so and closes the lobby", %{conn: conn} do
    {host, lobby} = hosted(%{"max_users" => 4})
    member = admin!()
    {:ok, _} = Lobbies.join_lobby(member, lobby.id)
    view = page(conn, member, ~p"/admin/lobbies/live?manage=#{lobby.id}")

    {:ok, _} = Lobbies.kick_user(host, lobby, Gamend.Accounts.get_user(member.id))
    send(view.pid, {:user_kicked, lobby.id, member.id})
    assert flash(view, :error) =~ "Removed"
    assert assigns(view).editing_lobby_id == nil
  end

  test "the pager and the lobby events redraw the list", %{conn: conn, admin: admin} do
    {_host, lobby} = hosted()
    view = page(conn, admin)

    render_click(view, "lobbies_next", %{})
    assert assigns(view).lobbies_page == 2
    render_click(view, "lobbies_prev", %{})
    render_click(view, "lobbies_prev", %{})
    assert assigns(view).lobbies_page == 1

    for message <- [
          {:lobby_created, lobby},
          {:lobby_updated, lobby},
          {:lobby_deleted, lobby.id},
          {:lobby_membership_changed, lobby.id},
          {:user_joined, lobby.id, admin.id},
          {:user_left, lobby.id, admin.id},
          {:user_kicked, lobby.id, Ecto.UUID.generate()},
          {:host_changed, lobby.id, admin.id},
          :something_else
        ] do
      send(view.pid, message)
    end

    assert has_element?(view, "#lobby-#{lobby.id}")
  end
end
