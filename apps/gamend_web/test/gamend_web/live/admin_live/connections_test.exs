defmodule GamendWeb.AdminLive.ConnectionsTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/connections")
    view
  end

  test "every filter narrows the table and goes back to its first page", %{
    conn: conn,
    admin: admin
  } do
    view = page(conn, admin)

    for filter <- ~w(websocket liveview webrtc all) do
      render_click(view, "filter-connections", %{"filter" => filter})
      state = :sys.get_state(view.pid).socket.assigns
      assert state.conn_filter == filter
      assert state.conn_page == 1
    end
  end

  test "the pager never leaves the pages there are", %{conn: conn, admin: admin} do
    view = page(conn, admin)

    render_click(view, "conn_prev_page", %{})
    assert :sys.get_state(view.pid).socket.assigns.conn_page == 1

    render_click(view, "conn_next_page", %{})
    assert :sys.get_state(view.pid).socket.assigns.conn_page == 1
  end

  test "the admin's own LiveView is a connection the page lists after a refresh", %{
    conn: conn,
    admin: admin
  } do
    view = page(conn, admin)
    send(view.pid, :refresh)
    send(view.pid, :unrelated)
    render_click(view, "filter-connections", %{"filter" => "liveview"})
    assert :sys.get_state(view.pid).socket.assigns.conn_filter == "liveview"
  end
end
