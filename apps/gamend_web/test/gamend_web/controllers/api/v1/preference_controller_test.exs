defmodule GamendWeb.Api.V1.PreferenceControllerTest do
  use GamendWeb.ConnCase

  alias Gamend.Accounts
  alias Gamend.Accounts.Preferences
  alias Gamend.AccountsFixtures
  alias GamendWeb.Auth.Guardian

  defp auth_conn(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  describe "PUT /api/v1/me/preferences" do
    test "saves a preference a client may set, and the row reads it back", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      assert %{"ok" => true} ==
               conn
               |> auth_conn(user)
               |> put("/api/v1/me/preferences", %{key: "theme", value: "dark"})
               |> json_response(200)

      assert Preferences.theme(Accounts.get_user(user.id)) == "dark"

      body =
        conn
        |> auth_conn(user)
        |> get("/api/v1/kv/preferences?user_id=#{user.id}")
        |> json_response(200)

      assert body["data"]["data"] == %{"theme" => "dark"}
    end

    test "refuses a key or a value not allowed, and saves nothing", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      for params <- [%{key: "theme", value: "purple"}, %{key: "timezone", value: "UTC"}] do
        assert %{"error" => "invalid_preference"} =
                 conn
                 |> auth_conn(user)
                 |> put("/api/v1/me/preferences", params)
                 |> json_response(422)
      end

      # No key at all: refused by the request check before the action.
      assert %{"error" => "validation_failed"} =
               conn |> auth_conn(user) |> put("/api/v1/me/preferences", %{}) |> json_response(422)

      assert Preferences.get(Accounts.get_user(user.id)) == %{}
    end

    test "needs a signed-in user", %{conn: conn} do
      assert conn
             |> put("/api/v1/me/preferences", %{key: "theme", value: "dark"})
             |> response(401)
    end
  end

  test "the row is its owner's alone", %{conn: conn} do
    owner = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {:ok, _owner} = Preferences.put_client(owner, "theme", "light")

    assert conn
           |> auth_conn(other)
           |> get("/api/v1/kv/preferences?user_id=#{owner.id}")
           |> response(403)

    assert conn |> auth_conn(other) |> get("/api/v1/kv/preferences") |> response(403)
  end
end
