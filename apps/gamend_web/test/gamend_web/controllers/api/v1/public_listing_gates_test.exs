defmodule GamendWeb.Api.V1.PublicListingGatesTest do
  @moduledoc """
  Tests for the LIST_*_ENABLED env flags that gate public listing endpoints
  and their matching realtime list channels.
  """
  use GamendWeb.ChannelCase, async: false

  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias Gamend.AccountsFixtures
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.UserSocket

  @endpoint GamendWeb.Endpoint

  setup do
    previous = Application.get_env(:gamend_web, GamendWeb.Features)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, GamendWeb.Features, previous),
        else: Application.delete_env(:gamend_web, GamendWeb.Features)
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp disable(feature) do
    config = Application.get_env(:gamend_web, GamendWeb.Features, [])

    Application.put_env(
      :gamend_web,
      GamendWeb.Features,
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

  describe "the payment API ways in" do
    test "the catalog and the Stripe checkout are on by default, and 404 when off", %{
      conn: conn
    } do
      user = AccountsFixtures.user_fixture()
      {:ok, token, _claims} = Guardian.encode_and_sign(user)
      authed = Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)

      assert conn |> get("/api/v1/payments/catalog") |> json_response(200)
      # On: the endpoint answers (a missing product here, not a missing route).
      assert authed |> post("/api/v1/payments/checkout/stripe", %{}) |> json_response(400)

      disable(:list_payments_catalog)
      disable(:stripe_checkout_api)

      assert conn |> get("/api/v1/payments/catalog") |> response(404)
      assert authed |> post("/api/v1/payments/checkout/stripe", %{}) |> response(404)
      # Signed out too: a 404, never a 401 that says the route exists.
      assert conn |> post("/api/v1/payments/checkout/stripe", %{}) |> response(404)
      # The rest of the payments API is not part of either flag.
      assert authed |> get("/api/v1/payments/entitlements") |> json_response(200)
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

  describe "USER_IMAGE_UPLOADS_ENABLED=false" do
    # Avatars and group icons are the only surfaces on which a player can put an
    # arbitrary image into public, unauthenticated storage. A host whose game
    # does not use them should be able to close them outright rather than run an
    # unscreened image surface it never asked for.
    setup do
      user = AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)

      %{
        authed:
          Plug.Conn.put_req_header(
            Phoenix.ConnTest.build_conn(),
            "authorization",
            "Bearer " <> token
          ),
        user: user
      }
    end

    test "avatar upload endpoints return 404", %{authed: authed} do
      disable(:user_image_uploads)

      assert authed |> post("/api/v1/me/avatar/upload_url", %{}) |> response(404)
      assert authed |> post("/api/v1/me/avatar", %{}) |> response(404)
    end

    test "group icon endpoints return 404", %{authed: authed, user: user} do
      # A real group the caller owns: a made-up id 404s whether or not the gate
      # is closed, so the test would pass for the wrong reason.
      {:ok, group} = Gamend.Groups.create_group(user.id, %{"title" => "Crew"})

      disable(:user_image_uploads)

      assert authed |> post("/api/v1/groups/#{group.id}/icon/upload_url", %{}) |> response(404)
      assert authed |> post("/api/v1/groups/#{group.id}/icon", %{}) |> response(404)
    end

    test "the rest of the account routes are unaffected", %{authed: authed} do
      disable(:user_image_uploads)

      # The gate must not take the whole /me surface with it — these share a
      # path prefix but not the risk.
      assert authed |> get("/api/v1/me") |> json_response(200)
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
               |> subscribe_and_join(GamendWeb.LobbiesChannel, "lobbies")
    end
  end

  describe "LIST_MATCHMAKING_ENABLED=false" do
    # Queue stats moved to the public stats surface and are gated by
    # :public_stats now (see StatsControllerTest); this flag no longer
    # covers them, only the caller's own ticket endpoints stay unaffected.
    test "own-ticket endpoints stay", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)
      authed = Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)

      disable(:list_matchmaking)

      # Answered by the endpoint (no ticket), not refused by the gate.
      assert authed |> get("/api/v1/matchmaking/tickets/me") |> json_response(404) ==
               %{"error" => "not_queued"}
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
               connect_user_socket() |> subscribe_and_join(GamendWeb.GroupsChannel, "groups")
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
               |> subscribe_and_join(GamendWeb.LobbiesChannel, "lobbies")

      assert {:ok, _, _socket} =
               connect_user_socket() |> subscribe_and_join(GamendWeb.GroupsChannel, "groups")
    end
  end

  defp connect_user_socket do
    user = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end
end
