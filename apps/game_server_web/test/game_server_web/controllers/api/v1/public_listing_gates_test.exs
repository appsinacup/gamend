defmodule GameServerWeb.Api.V1.PublicListingGatesTest do
  @moduledoc """
  Tests for the LIST_*_ENABLED env flags that gate public listing endpoints
  and their matching realtime list channels.
  """
  use GameServerWeb.ChannelCase, async: false

  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias GameServer.AccountsFixtures
  alias GameServerWeb.Auth.Guardian
  alias GameServerWeb.UserSocket

  @endpoint GameServerWeb.Endpoint

  setup do
    previous = Application.get_env(:game_server_web, GameServerWeb.Features)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:game_server_web, GameServerWeb.Features, previous),
        else: Application.delete_env(:game_server_web, GameServerWeb.Features)
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp disable(feature) do
    config = Application.get_env(:game_server_web, GameServerWeb.Features, [])

    Application.put_env(
      :game_server_web,
      GameServerWeb.Features,
      Keyword.put(config, feature, false)
    )
  end

  describe "defaults (flags unset)" do
    test "public listing endpoints are reachable", %{conn: conn} do
      assert conn |> get("/api/v1/users") |> json_response(200)
      assert conn |> get("/api/v1/lobbies") |> json_response(200)
      assert conn |> get("/api/v1/groups") |> json_response(200)
    end
  end

  describe "LIST_USERS_ENABLED=false" do
    test "GET /users and /users/:id return 404", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      disable(:list_users)

      assert conn |> get("/api/v1/users") |> response(404)
      assert conn |> get("/api/v1/users/#{user.id}") |> response(404)
    end
  end

  describe "LIST_LOBBIES_ENABLED=false" do
    test "GET /lobbies returns 404", %{conn: conn} do
      disable(:list_lobbies)

      assert conn |> get("/api/v1/lobbies") |> response(404)
    end

    test "joining the lobbies channel is rejected" do
      disable(:list_lobbies)

      assert {:error, %{reason: "listing_disabled"}} =
               connect_user_socket()
               |> subscribe_and_join(GameServerWeb.LobbiesChannel, "lobbies")
    end
  end

  describe "LIST_MATCHMAKING_ENABLED=false" do
    test "GET /matchmaking/stats returns 404; own-ticket endpoints stay", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)
      authed = Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)

      disable(:list_matchmaking)

      assert authed |> get("/api/v1/matchmaking/stats") |> response(404)
      # The caller's own ticket endpoints are authenticated, not gated.
      assert authed |> get("/api/v1/matchmaking/tickets/me") |> json_response(200)
    end
  end

  describe "LIST_GROUPS_ENABLED=false" do
    test "GET /groups, /groups/:id and /groups/:id/members return 404", %{conn: conn} do
      disable(:list_groups)

      assert conn |> get("/api/v1/groups") |> response(404)
      assert conn |> get("/api/v1/groups/1") |> response(404)
      assert conn |> get("/api/v1/groups/1/members") |> response(404)
    end

    test "joining the groups channel is rejected" do
      disable(:list_groups)

      assert {:error, %{reason: "listing_disabled"}} =
               connect_user_socket() |> subscribe_and_join(GameServerWeb.GroupsChannel, "groups")
    end
  end

  describe "LIST_LEADERBOARDS_ENABLED=false" do
    test "public leaderboard endpoints return 404", %{conn: conn} do
      disable(:list_leaderboards)

      assert conn |> get("/api/v1/leaderboards") |> response(404)
      assert conn |> get("/api/v1/leaderboards/some-slug") |> response(404)
      assert conn |> post("/api/v1/leaderboards/resolve", %{slugs: []}) |> response(404)
    end
  end

  describe "LIST_QUESTS_ENABLED=false" do
    test "public quest endpoints return 404", %{conn: conn} do
      disable(:list_quests)

      assert conn |> get("/api/v1/quests") |> response(404)
      assert conn |> get("/api/v1/quests/user/#{Ecto.UUID.generate()}") |> response(404)
    end
  end

  describe "browser list pages honor the same flags" do
    test "/groups, /leaderboards, /quests 404 when disabled", %{conn: conn} do
      disable(:list_groups)
      disable(:list_leaderboards)
      disable(:list_quests)

      assert_error_sent 404, fn -> get(conn, "/groups") end
      assert_error_sent 404, fn -> get(conn, "/leaderboards") end
      assert_error_sent 404, fn -> get(conn, "/quests") end
    end

    test "pages render when flags are unset", %{conn: conn} do
      assert conn |> get("/groups") |> html_response(200)
      assert conn |> get("/leaderboards") |> html_response(200)
      assert conn |> get("/quests") |> html_response(200)
    end
  end

  describe "channels with flags enabled" do
    test "lobbies and groups channels join normally" do
      assert {:ok, _, _socket} =
               connect_user_socket()
               |> subscribe_and_join(GameServerWeb.LobbiesChannel, "lobbies")

      assert {:ok, _, _socket} =
               connect_user_socket() |> subscribe_and_join(GameServerWeb.GroupsChannel, "groups")
    end
  end

  defp connect_user_socket do
    user = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end
end
