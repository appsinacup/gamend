defmodule GamendWeb.AdminLive.GroupsActionsTest do
  # The admin groups page's controls the render test did not press: filters,
  # sorting, paging, selecting and bulk deleting, the edit form, and the
  # members panel closed.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    owner = AccountsFixtures.user_fixture()

    {:ok, group} =
      Groups.create_group(owner.id, %{
        "title" => "Admin test group #{System.unique_integer([:positive])}"
      })

    %{admin: admin, group: group}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/groups")
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns
  defp listed?(view, group), do: Enum.any?(assigns(view).groups, &(&1.id == group.id))

  test "filters, sorting and paging keep the group listed", %{
    conn: conn,
    admin: admin,
    group: group
  } do
    view = page(conn, admin)
    assert listed?(view, group)

    render_change(view, "filter", %{"sort_by" => "inserted_at"})
    render_click(view, "sort", %{"sort_by" => "updated_at"})
    render_click(view, "admin_groups_next", %{})
    render_click(view, "admin_groups_prev", %{})
    render_click(view, "admin_groups_page_size", %{"size" => "50"})
    assert listed?(view, group)
  end

  test "a group selected and bulk deleted is gone", %{conn: conn, admin: admin, group: group} do
    view = page(conn, admin)
    render_click(view, "toggle_select_all", %{})
    assert MapSet.member?(assigns(view).selected_ids, to_string(group.id))
    render_click(view, "toggle_select_all", %{})
    assert MapSet.size(assigns(view).selected_ids) == 0

    render_click(view, "toggle_select", %{"id" => group.id})
    assert MapSet.member?(assigns(view).selected_ids, to_string(group.id))
    render_click(view, "bulk_delete", %{})
    assert Groups.get_group(group.id) == nil
  end

  test "the edit form opens and cancels; the members panel opens and closes", %{
    conn: conn,
    admin: admin,
    group: group
  } do
    view = page(conn, admin)
    render_click(view, "edit_group", %{"id" => group.id})
    assert assigns(view).selected_group.id == group.id
    render_click(view, "cancel_edit", %{})
    assert assigns(view).selected_group == nil

    render_click(view, "view_members", %{"id" => group.id})
    assert assigns(view).members != []
    render_click(view, "close_members", %{})
    assert assigns(view).selected_group == nil
  end
end
