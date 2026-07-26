defmodule GameServerWeb.Api.V1.Admin.ReadyChecksAdminControllerTest do
  use GameServerWeb.ConnCase, async: false

  alias GameServer.Accounts
  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServer.ReadyChecks
  alias GameServerWeb.Auth.Guardian

  defp bearer_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "admin-ready", host_id: host.id})
    {:ok, _} = Lobbies.join_lobby(member, lobby.id)

    %{
      admin_conn: bearer_conn(conn, admin),
      plain_conn: conn,
      host: host,
      member: member,
      lobby: lobby
    }
  end

  test "GET /ready_checks lists with filters and pagination meta", ctx do
    {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

    conn = get(ctx.admin_conn, "/api/v1/admin/ready_checks", %{"status" => "pending"})
    assert %{"data" => [row], "meta" => meta} = json_response(conn, 200)

    assert row["id"] == check.id
    assert row["kind"] == "ready"
    assert row["lobby_id"] == ctx.lobby.id
    assert length(row["participants"]) == 2
    assert meta["total_count"] == 1

    # A filter that matches nothing still returns the envelope.
    conn = get(ctx.admin_conn, "/api/v1/admin/ready_checks", %{"status" => "passed"})
    assert %{"data" => []} = json_response(conn, 200)
  end

  test "DELETE /ready_checks/:id force-cancels a pending check", ctx do
    {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

    conn = delete(ctx.admin_conn, "/api/v1/admin/ready_checks/#{check.id}")
    assert %{"data" => %{"status" => "cancelled"}} = json_response(conn, 200)

    # And is not repeatable.
    conn = delete(ctx.admin_conn, "/api/v1/admin/ready_checks/#{check.id}")
    assert json_response(conn, 404)
  end

  test "DELETE /ready_checks/:id 404s on an unknown id", ctx do
    conn = delete(ctx.admin_conn, "/api/v1/admin/ready_checks/#{Ecto.UUID.generate()}")
    assert json_response(conn, 404)
  end

  test "GET /ready_checks/stats counts by status", ctx do
    {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])
    {:ok, _} = ReadyChecks.cancel(check)

    conn = get(ctx.admin_conn, "/api/v1/admin/ready_checks/stats")
    assert %{"data" => %{"cancelled" => 1}} = json_response(conn, 200)
  end

  test "a non-admin is refused", ctx do
    conn = ctx.plain_conn |> bearer_conn(ctx.host) |> get("/api/v1/admin/ready_checks")
    assert json_response(conn, 403)
  end
end
