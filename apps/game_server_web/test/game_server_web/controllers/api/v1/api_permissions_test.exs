defmodule GameServerWeb.Api.V1.ApiPermissionsTest do
  @moduledoc """
  Permission tests for ALL API endpoints.
  Verifies that protected endpoints return 401 without auth,
  and admin endpoints return 403 for non-admin users.
  """
  use GameServerWeb.ConnCase, async: false

  alias GameServer.AccountsFixtures
  alias GameServerWeb.Auth.Guardian

  defp bearer_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  # -------------------------------------------------------------------------
  # Authenticated API endpoints → 401 without token
  # -------------------------------------------------------------------------

  describe "authenticated API endpoints return 401 without token" do
    @auth_endpoints [
      # Me
      {:get, "/api/v1/me"},
      {:delete, "/api/v1/me"},
      # Lobby (auth)
      {:post, "/api/v1/lobbies"},
      {:get, "/api/v1/lobbies/1"},
      {:post, "/api/v1/lobbies/1/join"},
      {:post, "/api/v1/lobbies/quick_join"},
      {:patch, "/api/v1/lobbies"},
      {:post, "/api/v1/lobbies/leave"},
      {:post, "/api/v1/lobbies/kick"},
      # Ready checks
      {:post, "/api/v1/lobbies/ready_check"},
      {:delete, "/api/v1/lobbies/ready_check"},
      {:get, "/api/v1/me/ready_check"},
      {:post, "/api/v1/me/ready_check"},
      # Friends
      {:post, "/api/v1/friends"},
      {:get, "/api/v1/me/friends"},
      {:get, "/api/v1/me/friend_requests"},
      {:get, "/api/v1/me/blocked"},
      {:post, "/api/v1/friends/1/accept"},
      {:post, "/api/v1/friends/1/reject"},
      {:post, "/api/v1/friends/1/block"},
      {:post, "/api/v1/friends/1/unblock"},
      {:delete, "/api/v1/friends/1"},
      # Notifications
      {:get, "/api/v1/notifications"},
      {:post, "/api/v1/notifications"},
      {:delete, "/api/v1/notifications"},
      # Groups (auth)
      {:post, "/api/v1/groups"},
      {:patch, "/api/v1/groups/1"},
      {:post, "/api/v1/groups/1/join"},
      {:post, "/api/v1/groups/1/leave"},
      {:post, "/api/v1/groups/1/kick"},
      {:post, "/api/v1/groups/1/promote"},
      {:post, "/api/v1/groups/1/demote"},
      {:get, "/api/v1/groups/1/join_requests"},
      {:post, "/api/v1/groups/1/invite"},
      {:get, "/api/v1/groups/invitations"},
      {:get, "/api/v1/groups/me"},
      {:get, "/api/v1/groups/sent_invitations"},
      # KV
      {:get, "/api/v1/kv/test_key"},
      # Hooks
      {:get, "/api/v1/hooks"},
      {:post, "/api/v1/hooks/call"},
      # Leaderboards (auth)
      {:get, "/api/v1/leaderboards/1/records/me"},
      # Parties
      {:get, "/api/v1/parties/me"},
      {:post, "/api/v1/parties"},
      {:patch, "/api/v1/parties"},
      {:post, "/api/v1/parties/leave"},
      {:post, "/api/v1/parties/kick"},
      {:post, "/api/v1/parties/invite"},
      {:post, "/api/v1/parties/invite/cancel"},
      {:post, "/api/v1/parties/invite/accept"},
      {:post, "/api/v1/parties/invite/decline"},
      {:get, "/api/v1/parties/invitations"},
      {:post, "/api/v1/parties/create_lobby"},
      {:post, "/api/v1/parties/join_lobby/1"},
      # Chat
      {:get, "/api/v1/chat/messages"},
      {:get, "/api/v1/chat/messages/1"},
      {:post, "/api/v1/chat/messages"},
      {:post, "/api/v1/chat/read"},
      {:get, "/api/v1/chat/unread"},
      # Achievements (auth)
      {:get, "/api/v1/me/quests"},
      # Provider
      {:delete, "/api/v1/me/providers/google"},
      {:post, "/api/v1/me/device"},
      {:delete, "/api/v1/me/device"},
      # Password
      {:patch, "/api/v1/me/password"},
      {:patch, "/api/v1/me/display_name"}
    ]

    for {method, path} <- @auth_endpoints do
      test "#{String.upcase(to_string(method))} #{path} returns 401", %{conn: conn} do
        conn = dispatch_request(conn, unquote(method), unquote(path))
        assert json_response(conn, 401)
      end
    end
  end

  # -------------------------------------------------------------------------
  # Admin API endpoints → 401 without token, 403 for non-admin
  # -------------------------------------------------------------------------

  describe "admin API endpoints return 401 without token" do
    @admin_endpoints [
      # KV Admin
      {:get, "/api/v1/admin/kv/entries"},
      {:post, "/api/v1/admin/kv/entries"},
      {:put, "/api/v1/admin/kv"},
      {:delete, "/api/v1/admin/kv"},
      # Leaderboards Admin
      {:post, "/api/v1/admin/leaderboards"},
      # Lobbies Admin
      {:get, "/api/v1/admin/lobbies"},
      # Users Admin
      {:delete, "/api/v1/admin/users/1"},
      # Notifications Admin
      {:get, "/api/v1/admin/notifications"},
      {:post, "/api/v1/admin/notifications"},
      # Groups Admin
      {:get, "/api/v1/admin/groups"},
      # Sessions Admin
      {:get, "/api/v1/admin/sessions"},
      # Chat Admin
      {:get, "/api/v1/admin/chat"},
      # Ready checks Admin
      {:get, "/api/v1/admin/ready_checks"},
      {:get, "/api/v1/admin/ready_checks/stats"},
      {:delete, "/api/v1/admin/ready_checks/1"},
      # Achievements Admin
      {:get, "/api/v1/admin/quests"},
      {:post, "/api/v1/admin/quests"}
    ]

    for {method, path} <- @admin_endpoints do
      test "#{String.upcase(to_string(method))} #{path} returns 401", %{conn: conn} do
        conn = dispatch_request(conn, unquote(method), unquote(path))
        assert json_response(conn, 401)
      end
    end
  end

  describe "admin API endpoints return 403 for non-admin users" do
    setup do
      # Ensure a first user exists so the fixture user is not auto-promoted
      _first = AccountsFixtures.user_fixture()
      user = AccountsFixtures.user_fixture()
      assert user.is_admin == false
      %{user: user}
    end

    for {method, path} <- @admin_endpoints do
      test "#{String.upcase(to_string(method))} #{path} returns 403", %{
        conn: conn,
        user: user
      } do
        conn = conn |> bearer_conn(user) |> dispatch_request(unquote(method), unquote(path))
        assert json_response(conn, 403)
      end
    end
  end

  # -------------------------------------------------------------------------
  # Public API endpoints → should work without auth (200)
  # -------------------------------------------------------------------------

  describe "public API endpoints work without authentication" do
    @public_endpoints [
      {:get, "/api/v1/health"},
      {:get, "/api/v1/users"},
      {:get, "/api/v1/lobbies"},
      {:get, "/api/v1/leaderboards"},
      {:get, "/api/v1/groups"},
      {:get, "/api/v1/quests"}
    ]

    for {method, path} <- @public_endpoints do
      test "#{String.upcase(to_string(method))} #{path} returns 200", %{conn: conn} do
        conn =
          conn
          |> put_req_header("content-type", "application/json")
          |> dispatch_request(unquote(method), unquote(path))

        assert conn.status == 200
      end
    end
  end

  # -------------------------------------------------------------------------
  # Helper
  # -------------------------------------------------------------------------

  defp dispatch_request(conn, :get, path), do: get(conn, path)
  defp dispatch_request(conn, :post, path), do: post(conn, path, %{})
  defp dispatch_request(conn, :patch, path), do: patch(conn, path, %{})
  defp dispatch_request(conn, :put, path), do: put(conn, path, %{})
  defp dispatch_request(conn, :delete, path), do: delete(conn, path)
end
