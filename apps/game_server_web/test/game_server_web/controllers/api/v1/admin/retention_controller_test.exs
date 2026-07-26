defmodule GameServerWeb.Api.V1.Admin.RetentionControllerTest do
  use GameServerWeb.ConnCase, async: false

  alias GameServer.Accounts.User
  alias GameServer.Repo
  alias GameServerWeb.Auth.Guardian

  setup %{conn: conn} do
    admin = GameServer.AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  test "requires admin" do
    user = GameServer.AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    conn = build_conn() |> put_req_header("authorization", "Bearer " <> token)

    assert json_response(get(conn, "/api/v1/admin/retention"), 403)
    assert json_response(post(conn, "/api/v1/admin/retention/run"), 403)
  end

  test "reports the last sweep", %{conn: conn} do
    body = json_response(get(conn, "/api/v1/admin/retention"), 200)

    assert Map.has_key?(body, "last_run_at")
    assert Map.has_key?(body, "duration_ms")
    assert is_map(body["results"])
  end

  # The sweeper is not supervised under test, so a manual run has nothing to
  # call - which is exactly the degraded case the endpoint has to report.
  test "reports unavailable when the sweeper is not running", %{conn: conn} do
    assert %{"error" => error} = json_response(post(conn, "/api/v1/admin/retention/run"), 503)
    assert error =~ "not running"
  end
end
