defmodule GameServerWeb.Api.V1.Admin.LobbyAdminControllerTest do
  use GameServerWeb.ConnCase, async: false

  alias GameServer.Accounts
  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServerWeb.Auth.Guardian

  defp bearer_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})

    %{admin_conn: bearer_conn(conn, admin)}
  end

  test "PATCH /admin/lobbies/:id updates a hostless lobby players may not touch", %{
    admin_conn: admin_conn
  } do
    {:ok, lobby} = Lobbies.create_lobby(%{title: "hostless-admin-room", hostless: true})

    conn =
      patch(admin_conn, "/api/v1/admin/lobbies/#{lobby.id}", %{
        "title" => "Admin Renamed",
        "metadata" => %{"seed" => 7}
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["title"] == "Admin Renamed"

    reloaded = Lobbies.get_lobby(lobby.id)
    assert reloaded.metadata == %{"seed" => 7}
  end

  test "PATCH /admin/lobbies/:id updates a lobby the admin does not host", %{
    admin_conn: admin_conn
  } do
    host = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "hosted-admin-room", host_id: host.id})

    conn = patch(admin_conn, "/api/v1/admin/lobbies/#{lobby.id}", %{"is_locked" => true})

    assert %{"data" => data} = json_response(conn, 200)
    assert data["is_locked"] == true
  end
end
