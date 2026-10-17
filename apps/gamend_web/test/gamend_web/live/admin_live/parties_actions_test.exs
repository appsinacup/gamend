defmodule GamendWeb.AdminLive.PartiesActionsTest do
  # The admin parties page past creating one: filters, sorting and paging,
  # selecting and bulk deleting, the edit form, and a party's members opened,
  # added to and kicked.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Parties
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    leader = AccountsFixtures.user_fixture()
    {:ok, party} = Parties.create_party(leader, %{max_size: 4})
    %{admin: admin, leader: leader, party: party}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/parties")
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns
  defp listed?(view, party), do: Enum.any?(assigns(view).parties, &(&1.id == party.id))

  test "filters, sorting, paging and the create form's cancel", %{
    conn: conn,
    admin: admin,
    party: party
  } do
    view = page(conn, admin)
    assert listed?(view, party)

    render_change(view, "filter", %{"sort_by" => "inserted_at"})
    render_click(view, "sort", %{"sort_by" => "updated_at"})
    render_click(view, "admin_parties_next", %{})
    render_click(view, "admin_parties_prev", %{})
    render_click(view, "admin_parties_page_size", %{"size" => "50"})
    assert listed?(view, party)

    render_click(view, "show_create", %{})
    render_click(view, "cancel_create", %{})
    refute has_element?(view, "#party-create-form")
  end

  test "a party selected and bulk deleted is gone", %{conn: conn, admin: admin, party: party} do
    view = page(conn, admin)
    render_click(view, "toggle_select", %{"id" => party.id})
    assert MapSet.member?(assigns(view).selected_ids, to_string(party.id))
    render_click(view, "toggle_select", %{"id" => party.id})
    refute MapSet.member?(assigns(view).selected_ids, to_string(party.id))

    render_click(view, "toggle_select_all", %{})
    render_click(view, "bulk_delete", %{})
    assert Parties.get_party(party.id) == nil
  end

  test "the edit form opens and cancels", %{conn: conn, admin: admin, party: party} do
    view = page(conn, admin)
    render_click(view, "edit_party", %{"id" => party.id})
    assert assigns(view).selected_party.id == party.id
    render_click(view, "cancel_edit", %{})
    assert assigns(view).selected_party == nil
  end

  test "a member is added by id and kicked; a bad id is refused", %{
    conn: conn,
    admin: admin,
    party: party
  } do
    member = AccountsFixtures.user_fixture()
    view = page(conn, admin)
    render_click(view, "view_members", %{"id" => party.id})

    render_change(view, "update_add_member_id", %{"value" => "not-a-uuid"})
    render_click(view, "add_party_member", %{})
    refute Enum.any?(Parties.get_party_members(party.id), &(&1.id == member.id))

    render_change(view, "update_add_member_id", %{"value" => member.id})
    render_click(view, "add_party_member", %{})
    assert Enum.any?(Parties.get_party_members(party.id), &(&1.id == member.id))

    render_click(view, "kick_member", %{"party-id" => party.id, "user-id" => member.id})
    refute Enum.any?(Parties.get_party_members(party.id), &(&1.id == member.id))

    render_click(view, "close_members", %{})
    refute assigns(view).show_members
  end

  test "a player id that is a valid uuid but no account is refused", %{
    conn: conn,
    admin: admin,
    party: party
  } do
    view = page(conn, admin)
    render_click(view, "view_members", %{"id" => party.id})
    render_change(view, "update_add_member_id", %{"value" => Gamend.UUIDv7.generate()})
    render_click(view, "add_party_member", %{})
    assert length(Parties.get_party_members(party.id)) == 1
  end
end
