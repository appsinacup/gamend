defmodule GamendWeb.Api.V1.GroupInviteLinksApiTest do
  # A group's invite link over the API (`Gamend.Groups.InviteLinks`): an
  # admin reads, makes and turns off the link, and lists the group's pending
  # invitations; anyone signed in looks at the group a token opens and joins
  # through it.
  use GamendWeb.ConnCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias GamendWeb.Auth.Guardian

  setup do
    previous = Application.get_env(:gamend_core, Groups, [])

    Application.put_env(
      :gamend_core,
      Groups,
      Keyword.merge(previous, types: ["hidden", "private"], invites: :anyone)
    )

    on_exit(fn -> Application.put_env(:gamend_core, Groups, previous) end)

    # The first account is the site's admin; the people here are not.
    _first = AccountsFixtures.user_fixture()
    admin = AccountsFixtures.user_fixture()
    {:ok, group} = Groups.create_group(admin.id, %{"title" => "Night shift"})

    %{admin: admin, other: AccountsFixtures.user_fixture(), group: group}
  end

  defp auth(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  test "an admin makes, reads and turns off the link", %{conn: conn, admin: admin, group: group} do
    assert %{"error" => "not_found"} =
             conn
             |> auth(admin)
             |> get("/api/v1/groups/#{group.id}/invite_link")
             |> json_response(404)

    %{"data" => link} =
      conn |> auth(admin) |> post("/api/v1/groups/#{group.id}/invite_link") |> json_response(200)

    assert %{"group_id" => group_id, "token" => token, "url" => url, "uses" => 0} = link
    assert group_id == group.id
    assert url =~ "/users/groups/join/#{token}"

    assert %{"data" => %{"token" => ^token}} =
             conn
             |> auth(admin)
             |> get("/api/v1/groups/#{group.id}/invite_link")
             |> json_response(200)

    assert %{"ok" => true} =
             conn
             |> auth(admin)
             |> delete("/api/v1/groups/#{group.id}/invite_link")
             |> json_response(200)

    assert Groups.get_invite_link(group.id) == nil
  end

  test "only an admin touches the link or lists the invitations", %{
    conn: conn,
    other: other,
    group: group
  } do
    for request <- [
          &get(&1, "/api/v1/groups/#{group.id}/invite_link"),
          &post(&1, "/api/v1/groups/#{group.id}/invite_link"),
          &delete(&1, "/api/v1/groups/#{group.id}/invite_link"),
          &get(&1, "/api/v1/groups/#{group.id}/invites")
        ] do
      assert %{"error" => "not_admin"} = conn |> auth(other) |> request.() |> json_response(403)
    end
  end

  test "someone signed in looks at the link's group, then joins through it", %{
    conn: conn,
    admin: admin,
    other: other,
    group: group
  } do
    {:ok, %{token: token}} = Groups.create_invite_link(admin.id, group.id)

    assert %{"error" => "unauthenticated"} =
             conn |> get("/api/v1/groups/invite_links/#{token}") |> json_response(401)

    assert %{"data" => preview} =
             conn
             |> auth(other)
             |> get("/api/v1/groups/invite_links/#{token}")
             |> json_response(200)

    assert %{"group_title" => "Night shift", "member_count" => 1, "member" => false} = preview
    assert preview["creator_name"] == Gamend.Accounts.display_name(admin)

    assert %{"data" => %{"role" => "member"}} =
             conn
             |> auth(other)
             |> post("/api/v1/groups/invite_links/#{token}/join")
             |> json_response(200)

    assert Groups.member?(group.id, other.id)

    assert %{"error" => "already_member"} =
             conn
             |> auth(other)
             |> post("/api/v1/groups/invite_links/#{token}/join")
             |> json_response(409)

    assert %{"error" => "not_found"} =
             conn |> auth(other) |> get("/api/v1/groups/invite_links/nope") |> json_response(404)
  end

  test "an admin lists the group's pending invitations and cancels one another admin sent", %{
    conn: conn,
    admin: admin,
    other: other,
    group: group
  } do
    second = AccountsFixtures.user_fixture()
    {:ok, %{token: token}} = Groups.create_invite_link(admin.id, group.id)
    {:ok, _member} = Groups.join_by_invite_link(second.id, token)
    {:ok, _member} = Groups.promote_member(admin.id, group.id, second.id)
    {:ok, invite} = Groups.invite_to_group(second.id, group.id, other.id)

    assert %{"data" => [%{"id" => invite_id, "sender_id" => sender_id}], "meta" => meta} =
             conn
             |> auth(admin)
             |> get("/api/v1/groups/#{group.id}/invites")
             |> json_response(200)

    assert invite_id == invite.id
    assert sender_id == second.id
    assert meta["total_count"] == 1

    assert %{"ok" => true} =
             conn
             |> auth(admin)
             |> delete("/api/v1/groups/sent_invitations/#{invite.id}")
             |> json_response(200)

    assert {:ok, []} = Groups.list_group_invites(admin.id, group.id)
  end
end
