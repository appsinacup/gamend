defmodule GamendWeb.Api.V1.MeControllerTest do
  use GamendWeb.ConnCase

  alias GamendWeb.Auth.Guardian

  describe "GET /api/v1/me" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, "/api/v1/me")
      assert json_response(conn, 401)
    end

    test "returns user info when authenticated", %{conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()

      {:ok, token, _claims} = Guardian.encode_and_sign(user)

      conn = conn |> put_req_header("authorization", "Bearer " <> token) |> get("/api/v1/me")

      body = json_response(conn, 200)["data"]
      assert body["id"] == user.id
      assert body["email"] == user.email
      assert Map.has_key?(body, "display_name")
      refute Map.has_key?(body, "is_admin")
      assert Map.has_key?(body, "metadata")
      assert Map.has_key?(body, "lobby_id")
      assert body["lobby_id"] == ""
      assert body["last_seen_at"] == "1970-01-01T00:00:00Z"

      # Verify linked_providers and has_password fields
      assert Map.has_key?(body, "linked_providers")
      assert body["linked_providers"]["google"] == false
      assert body["linked_providers"]["facebook"] == false
      assert body["linked_providers"]["github"] == false
      assert body["linked_providers"]["discord"] == false
      assert body["linked_providers"]["apple"] == false
      assert body["linked_providers"]["steam"] == false
      assert body["linked_providers"]["device"] == false
      # user_fixture creates user via magic link, so no password
      assert body["has_password"] == false
    end
  end

  describe "PATCH /api/v1/me/display_name" do
    test "updates the authenticated user's display_name", %{conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> patch("/api/v1/me/display_name", %{display_name: "API Name"})

      assert json_response(conn, 200)["data"]["display_name"] == "API Name"

      reloaded = Gamend.Repo.get(Gamend.Accounts.User, user.id)
      assert reloaded.display_name == "API Name"
    end

    test "empty display_name does not return bad request", %{conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> patch("/api/v1/me/display_name", %{display_name: ""})

      assert conn.status == 200
      _body = json_response(conn, 200)
    end
  end

  describe "PATCH /api/v1/me/username" do
    test "sets the handle, lowercased, and echoes it back", %{conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> patch("/api/v1/me/username", %{username: "New.Handle"})

      assert %{"id" => id, "username" => "new.handle"} = json_response(conn, 200)["data"]
      assert id == user.id
    end
  end

  describe "PATCH /api/v1/me/password" do
    test "updates password for authenticated user", %{conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)

      new_password = Gamend.AccountsFixtures.valid_user_password()

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> patch("/api/v1/me/password", %{password: new_password})

      assert json_response(conn, 200)

      # reloaded and verify password works
      reloaded = Gamend.Repo.get(Gamend.Accounts.User, user.id)
      assert Gamend.Accounts.get_user_by_email_and_password(reloaded.email, new_password)
    end

    test "empty password returns bad request", %{conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> patch("/api/v1/me/password", %{password: ""})

      assert conn.status == 422
      body = json_response(conn, 422)
      assert Map.has_key?(body, "errors")
      assert Map.has_key?(body["errors"], "password")
    end
  end

  describe "password auth should not work for oauth-only account without password" do
    test "get_user_by_email_and_password returns nil for empty password", %{conn: _conn} do
      user = Gamend.AccountsFixtures.user_fixture(%{discord_id: "d123"})

      # user has no password, attempt to login with empty string should fail
      refute Gamend.Accounts.get_user_by_email_and_password(user.email, "")
      # and with any random string should also fail
      refute Gamend.Accounts.get_user_by_email_and_password(user.email, "pw")
    end
  end

  describe "DELETE /api/v1/me" do
    test "deletes the authenticated user's account", %{conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> delete("/api/v1/me")

      assert conn.status == 200

      # Ensure user was deleted
      assert Gamend.Repo.get(Gamend.Accounts.User, user.id) == nil
    end

    test "returns 401 when not authenticated", %{conn: conn} do
      conn = delete(conn, "/api/v1/me")
      assert json_response(conn, 401)
    end

    test "an account with a password is deleted only with it in the body", %{conn: conn} do
      _admin = Gamend.AccountsFixtures.user_fixture()

      user =
        Gamend.AccountsFixtures.user_fixture(%{email: "leaving@example.com"})
        |> Gamend.AccountsFixtures.set_password()

      {:ok, token, _} = Guardian.encode_and_sign(user)
      authed = put_req_header(conn, "authorization", "Bearer " <> token)

      refused = delete(authed, "/api/v1/me")
      assert json_response(refused, 401)["error"] == "invalid_current_password"

      wrong = delete(authed, "/api/v1/me", %{current_password: "not it at all"})
      assert json_response(wrong, 401)["error"] == "invalid_current_password"

      deleted = delete(authed, "/api/v1/me", %{current_password: "hello world!"})
      assert deleted.status == 200
      assert Gamend.Repo.get(Gamend.Accounts.User, user.id) == nil
    end
  end
end
