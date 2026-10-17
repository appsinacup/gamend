defmodule GamendWeb.AdminLive.UsersActionsTest do
  # The admin users page's controls the listing tests did not press: sorting
  # (a second press flips it), clearing a search, page size, select all, and
  # a user's panel: their sessions revoked one at a time or all at once, a
  # deletion they asked for cancelled, password sign-in unlocked.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    player = AccountsFixtures.user_fixture()
    %{admin: admin, player: player}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/users")
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "a column sorts descending, and a second press ascending", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    render_click(view, "sort_users", %{"field" => "email"})
    assert {assigns(view).sort_field, assigns(view).sort_dir} == {"email", "desc"}
    render_click(view, "sort_users", %{"field" => "email"})
    assert assigns(view).sort_dir == "asc"
    render_click(view, "sort_users", %{"field" => "inserted_at"})
    assert assigns(view).sort_dir == "desc"
  end

  test "a search cleared lists everyone again, page one", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    view = page(conn, admin)
    render_change(view, "search_users", %{"q" => "nobody-matches-this"})
    assert assigns(view).recent_users == []

    render_click(view, "clear_search", %{})
    assert assigns(view).search_query == ""
    assert Enum.any?(assigns(view).recent_users, &(&1.id == player.id))
  end

  test "page size, the pager, and select all", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    render_click(view, "admin_users_page_size", %{"size" => "50"})
    assert assigns(view).users_page_size == 50
    render_click(view, "admin_users_prev", %{})
    assert assigns(view).users_page == 1

    render_click(view, "toggle_select_all", %{})
    assert MapSet.size(assigns(view).selected_ids) == length(assigns(view).recent_users)
    render_click(view, "toggle_select_all", %{})
    assert MapSet.size(assigns(view).selected_ids) == 0
  end

  test "a user's sessions are revoked one at a time, then all at once", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    _ = Accounts.generate_user_session_token(player)
    _ = Accounts.generate_user_session_token(player)
    view = page(conn, admin)

    render_click(view, "edit_user", %{"id" => player.id})
    [first | _] = assigns(view).user_tokens
    render_click(view, "revoke_token", %{"id" => first.id})
    assert length(assigns(view).user_tokens) == 1

    render_click(view, "revoke_all_sessions", %{"user-id" => player.id})
    assert assigns(view).user_tokens == []

    render_click(view, "cancel_edit", %{})
    assert assigns(view).selected_user == nil
  end

  test "a deletion the player asked for is cancelled; sign-in is unlocked", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    later = DateTime.utc_now(:second) |> DateTime.add(7, :day)
    player |> Ecto.Changeset.change(deletion_scheduled_at: later) |> Repo.update!()
    view = page(conn, admin)
    render_click(view, "edit_user", %{"id" => player.id})
    assert has_element?(view, ~s([phx-click="cancel_user_deletion"]))

    render_click(view, "cancel_user_deletion", %{"id" => player.id})
    refute Repo.reload(player).deletion_scheduled_at

    render_click(view, "unlock_login", %{"id" => player.id})
    refute assigns(view).login_locked
  end

  test "a user deleted since the page loaded is answered on every action", %{
    conn: conn,
    admin: admin
  } do
    view = page(conn, admin)
    gone = Ecto.UUID.generate()

    for event <- ~w(edit_user cancel_user_deletion unlock_login delete_user) do
      render_click(view, event, %{"id" => gone})
    end

    assert assigns(view).selected_user == nil
  end
end
