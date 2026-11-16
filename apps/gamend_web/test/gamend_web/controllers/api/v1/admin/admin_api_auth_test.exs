defmodule GamendWeb.Api.V1.Admin.AdminApiAuthTest do
  use GamendWeb.ConnCase, async: false

  alias GamendWeb.Auth.Guardian

  defp bearer_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  test "admin endpoints require admin role", %{conn: conn} do
    # The Accounts context auto-promotes the very first user in the DB to admin.
    # Ensure the user under test is not the first-created user.
    _first_user = Gamend.AccountsFixtures.user_fixture()

    user = Gamend.AccountsFixtures.user_fixture()
    assert user.is_admin == false
    conn = conn |> bearer_conn(user)

    conn = get(conn, "/api/v1/admin/kv/entries")
    assert %{"error" => "forbidden"} = json_response(conn, 403)
  end
end
