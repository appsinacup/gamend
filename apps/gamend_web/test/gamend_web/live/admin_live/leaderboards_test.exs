defmodule GamendWeb.AdminLive.LeaderboardsTest do
  # The admin leaderboards page's forms and lists that nothing else drove:
  # filters, selecting rows, the new-board and new-season forms, editing and
  # cancelling, and a board's records opened, paged, added to and edited.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Leaderboards
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, board} =
      Leaderboards.create_leaderboard(%{
        slug: "admin_lb_#{System.unique_integer([:positive])}",
        title: "Weekly"
      })

    player = AccountsFixtures.user_fixture()
    {:ok, _} = Leaderboards.submit_score(board.id, player.id, 42)
    %{admin: admin, board: board}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/leaderboards")
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "filters, the pager and page size keep the board listed", %{
    conn: conn,
    admin: admin,
    board: board
  } do
    view = page(conn, admin)
    assert has_element?(view, "#admin-lb-#{board.id}")

    for filter <- ~w(active ended all),
        do: render_click(view, "set_filter", %{"filter" => filter})

    render_click(view, "next_page", %{})
    render_click(view, "prev_page", %{})
    render_click(view, "leaderboards_page_size", %{"size" => "50"})
    assert has_element?(view, "#admin-lb-#{board.id}")
  end

  test "select all selects every row, and again none", %{conn: conn, admin: admin, board: board} do
    view = page(conn, admin)
    render_click(view, "toggle_select_all", %{})
    assert MapSet.member?(assigns(view).selected_ids, to_string(board.id))
    render_click(view, "toggle_select_all", %{})
    assert MapSet.size(assigns(view).selected_ids) == 0
  end

  test "a new board's form opens and cancels; a new season starts from a board", %{
    conn: conn,
    admin: admin,
    board: board
  } do
    view = page(conn, admin)

    render_click(view, "new_leaderboard", %{})
    assert has_element?(view, "#leaderboard-form")
    render_click(view, "cancel_edit", %{})
    refute has_element?(view, "#leaderboard-form")

    render_click(view, "new_season_from", %{"id" => board.id})
    assert has_element?(view, "#leaderboard-form")
    assert assigns(view).form.params == %{} or assigns(view).form.data.slug == board.slug
    assert assigns(view).form.data.title == "Weekly"
  end

  test "a board opens for editing with its own values", %{conn: conn, admin: admin, board: board} do
    view = page(conn, admin)
    render_click(view, "edit_leaderboard", %{"id" => board.id})
    assert assigns(view).selected_leaderboard.id == board.id
    assert has_element?(view, "#leaderboard-form")
  end

  test "a board's records open, page, and close; a record opens for editing", %{
    conn: conn,
    admin: admin,
    board: board
  } do
    view = page(conn, admin)
    render_click(view, "view_records", %{"id" => board.id})
    [record] = assigns(view).records
    assert has_element?(view, "#record-#{record.id}")

    render_click(view, "records_next_page", %{})
    render_click(view, "records_prev_page", %{})

    render_click(view, "add_record", %{})
    assert has_element?(view, "#record-form")
    render_click(view, "cancel_record_edit", %{})
    refute has_element?(view, "#record-form")

    render_click(view, "edit_record", %{"id" => record.id})
    assert assigns(view).editing_record.id == record.id

    render_click(view, "close_records", %{})
    refute assigns(view).viewing_records
  end

  test "a board or record that no longer exists is answered, not crashed on", %{
    conn: conn,
    admin: admin
  } do
    view = page(conn, admin)
    missing = Ecto.UUID.generate()

    for event <- ~w(new_season_from edit_leaderboard view_records edit_record) do
      render_click(view, event, %{"id" => missing})
    end

    assert render(view)
  end
end
