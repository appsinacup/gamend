defmodule GamendWeb.GroupsLiveHiddenTest do
  # A hidden group exists only for its members, on `/groups/:id` as on
  # `GET /api/v1/groups/:id`: its page is its roster.
  use GamendWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.Groups

  setup do
    owner = AccountsFixtures.user_fixture()
    {:ok, group} = Groups.create_group(owner.id, %{"title" => "Secret", "type" => "hidden"})
    %{owner: owner, group: group}
  end

  test "a visitor gets not found", %{conn: conn, group: group} do
    assert {:error, {_redirect, %{to: "/groups"}}} = live(conn, ~p"/groups/#{group.id}")
  end

  test "a signed-in stranger gets not found", %{conn: conn, group: group} do
    stranger = AccountsFixtures.user_fixture()

    assert {:error, {_redirect, %{to: "/groups"}}} =
             conn |> log_in_user(stranger) |> live(~p"/groups/#{group.id}")
  end

  test "a member sees it", %{conn: conn, owner: owner, group: group} do
    {:ok, view, _html} = conn |> log_in_user(owner) |> live(~p"/groups/#{group.id}")

    assert :sys.get_state(view.pid).socket.assigns.selected_group.id == group.id
  end
end
