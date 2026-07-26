defmodule GameServerWeb.AuthControllerTest do
  use GameServerWeb.ConnCase, async: false

  alias GameServer.Accounts
  alias GameServer.AccountsFixtures
  alias GameServer.OAuthSessions
  alias GameServer.SettingsHelpers

  defp put_provider_setting(key, value) do
    orig = SettingsHelpers.get(:game_server_core, GameServer.OAuth.Providers, key)
    SettingsHelpers.put(:game_server_core, GameServer.OAuth.Providers, key, value)

    on_exit(fn ->
      SettingsHelpers.put(:game_server_core, GameServer.OAuth.Providers, key, orig)
    end)
  end

  test "request redirects to provider (discord)", %{conn: conn} do
    put_provider_setting(:discord_client_id, "cid-123")

    conn = get(conn, "/auth/discord")
    # Ueberauth strategies may use slightly different endpoints; assert by host and client_id
    assert redirected_to(conn) =~ "discord.com"
    assert redirected_to(conn) =~ "client_id=cid-123"
  end

  test "request redirects to provider (google)", %{conn: conn} do
    put_provider_setting(:google_client_id, "google-123")

    conn = get(conn, "/auth/google")
    assert redirected_to(conn) =~ "accounts.google.com"
    assert redirected_to(conn) =~ "client_id=google-123"
  end

  test "request redirects to provider (facebook)", %{conn: conn} do
    put_provider_setting(:facebook_client_id, "fb-123")

    conn = get(conn, "/auth/facebook")
    assert redirected_to(conn) =~ "facebook.com"
    assert redirected_to(conn) =~ "client_id=fb-123"
  end

  test "request redirects to provider (apple)", %{conn: conn} do
    put_provider_setting(:apple_client_id, "apple-123")

    conn = get(conn, "/auth/apple")
    assert redirected_to(conn) =~ "appleid.apple.com"
    assert redirected_to(conn) =~ "client_id=apple-123"
  end

  test "callback (discord) on error with state creates oauth session", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    defmodule TestExchanger do
      def exchange_discord_code(_code, _client_id, _secret, _redirect), do: {:error, :boom}
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger)

    on_exit(fn -> Application.put_env(:game_server_web, :oauth_exchanger, orig) end)

    session_id = "session-#{System.unique_integer([:positive])}"

    # API flow should create/update an existing session; create a pending session first
    OAuthSessions.create_session(session_id, %{provider: "discord", status: "pending"})

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/discord/callback?code=abc&state=#{session_id}")
    end)

    # session should be created with error status
    sess = OAuthSessions.get_session(session_id)
    assert sess.status == "error"
  end

  test "callback (discord) on error without state shows flash", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    defmodule TestExchanger.ErrorDiscord do
      def exchange_discord_code(_code, _client_id, _secret, _redirect), do: {:error, :boom}
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.ErrorDiscord)

    on_exit(fn -> Application.put_env(:game_server_web, :oauth_exchanger, orig) end)

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/discord/callback?code=abc")
    end)

    conn = get(conn, "/auth/discord/callback?code=abc")
    assert redirected_to(conn) =~ "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Failed to authenticate"
  end

  test "callback (discord) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    defmodule TestExchanger.SuccessDiscord do
      def exchange_discord_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"id" => "d123", "email" => "d@example.com", "username" => "duser"}}
      end
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.SuccessDiscord)

    on_exit(fn -> Application.put_env(:game_server_web, :oauth_exchanger, orig) end)

    # browser flow (no state) should login / redirect
    conn1 = get(conn, "/auth/discord/callback?code=abc")
    assert redirected_to(conn1) =~ "/"

    # api flow with state should create a completed session
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "discord", status: "pending"})

    _conn2 = get(conn, "/auth/discord/callback?code=abc&state=#{session_id}")

    session = OAuthSessions.get_session(session_id)
    assert session.status == "completed"
  end

  test "callback (google) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    defmodule TestExchanger.SuccessGoogle do
      def exchange_google_code(_code, _client_id, _secret, _redirect) do
        {:ok,
         %{
           "id" => "g123",
           "email" => "g@example.com",
           "picture" => "https://img/1.png",
           "name" => "Gname"
         }}
      end
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.SuccessGoogle)

    on_exit(fn -> Application.put_env(:game_server_web, :oauth_exchanger, orig) end)

    # browser flow
    conn1 = get(conn, "/auth/google/callback?code=xxx")
    assert redirected_to(conn1) =~ "/"

    # api flow with state
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "google", status: "pending"})

    _conn2 = get(conn, "/auth/google/callback?code=xxx&state=#{session_id}")

    session = OAuthSessions.get_session(session_id)
    assert session.status == "completed"
  end

  test "callback (google) error creates session with error status", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    defmodule TestExchanger.ErrorGoogle do
      def exchange_google_code(_code, _client_id, _secret, _redirect), do: {:error, :failed}
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.ErrorGoogle)

    on_exit(fn -> Application.put_env(:game_server_web, :oauth_exchanger, orig) end)

    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "google", status: "pending"})

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/google/callback?code=xxx&state=#{session_id}")
    end)

    session = OAuthSessions.get_session(session_id)
    assert session.status == "error"
  end

  test "callback (facebook) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    defmodule TestExchanger.SuccessFacebook do
      def exchange_facebook_code(_code, _client_id, _secret, _redirect) do
        {:ok,
         %{
           "id" => "fb123",
           "email" => "fb@example.com",
           "picture" => %{"data" => %{"url" => "https://fb/img.png"}},
           "name" => "Fb name"
         }}
      end
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.SuccessFacebook)

    on_exit(fn -> Application.put_env(:game_server_web, :oauth_exchanger, orig) end)

    # browser flow
    conn1 = get(conn, "/auth/facebook/callback?code=yyy")
    assert redirected_to(conn1) =~ "/"

    # api flow with state
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "facebook", status: "pending"})

    _conn2 = get(conn, "/auth/facebook/callback?code=yyy&state=#{session_id}")

    session = OAuthSessions.get_session(session_id)
    assert session.status == "completed"
  end

  test "callback (facebook) error creates session with error status", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    defmodule TestExchanger.ErrorFacebook do
      def exchange_facebook_code(_code, _client_id, _secret, _redirect), do: {:error, :failed}
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.ErrorFacebook)

    on_exit(fn -> Application.put_env(:game_server_web, :oauth_exchanger, orig) end)

    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "facebook", status: "pending"})

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/facebook/callback?code=yyy&state=#{session_id}")
    end)

    session = OAuthSessions.get_session(session_id)
    assert session.status == "error"
  end

  test "callback (apple) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    defmodule TestExchanger.SuccessApple do
      def exchange_apple_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"sub" => "apple123", "email" => "apple@example.com"}}
      end
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.SuccessApple)

    # Set up Apple client_secret in cache to avoid needing APPLE_PRIVATE_KEY
    case :ets.info(:apple_oauth_cache) do
      :undefined -> :ets.new(:apple_oauth_cache, [:named_table, :public, :set])
      _ -> :ok
    end

    expires_at = System.system_time(:second) + 10_000

    :ets.insert(
      :apple_oauth_cache,
      {{:client_secret, "com.example.web"}, "test-secret", expires_at}
    )

    on_exit(fn ->
      Application.put_env(:game_server_web, :oauth_exchanger, orig)
      # Only delete if table exists
      case :ets.info(:apple_oauth_cache) do
        :undefined -> :ok
        _ -> :ets.delete(:apple_oauth_cache)
      end
    end)

    # Browser flow: this intentionally posts with build_conn() instead of reusing
    # auth_conn. Apple returns via cross-site form_post, so SameSite=Lax can omit
    # the browser session cookie. Do not re-add a session-cookie fallback.
    auth_conn = get(conn, "/auth/apple")
    state = oauth_state_from_redirect(auth_conn)

    conn1 = post(build_conn(), "/auth/apple/callback", %{"code" => "xxx", "state" => state})
    assert redirected_to(conn1) == "/"
    assert Phoenix.Flash.get(conn1.assigns.flash, :error) == nil

    # api flow with state
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "apple", status: "pending"})

    _conn2 = post(conn, "/auth/apple/callback", %{"code" => "xxx", "state" => session_id})

    session = OAuthSessions.get_session(session_id)
    assert session.status == "completed"
  end

  test "callback (apple) browser form_post works without callback session cookie", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)
    oauth_orig = Application.get_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    Application.put_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth,
      client_id: "com.example.web",
      client_secret: "dummy-secret"
    )

    defmodule TestExchanger.AppleNoCookie do
      def exchange_apple_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"sub" => "apple-no-cookie", "email" => "apple-no-cookie@example.com"}}
      end
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.AppleNoCookie)

    on_exit(fn ->
      Application.put_env(:game_server_web, :oauth_exchanger, orig)
      Application.put_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth, oauth_orig)
    end)

    auth_conn = get(conn, "/auth/apple")
    state = oauth_state_from_redirect(auth_conn)
    assert OAuthSessions.get_session(state).status == "pending"

    callback_conn =
      post(build_conn(), "/auth/apple/callback", %{"code" => "xxx", "state" => state})

    assert redirected_to(callback_conn) == "/"
    assert Phoenix.Flash.get(callback_conn.assigns.flash, :error) == nil
    assert Accounts.get_user_by_apple_id("apple-no-cookie")
    assert OAuthSessions.get_session(state).status == "completed"

    # Server-side state is single-use. Session-cookie fallback would wrongly let
    # browser callbacks depend on a cookie Apple cannot guarantee on form_post.
    replay_conn = post(build_conn(), "/auth/apple/callback", %{"code" => "xxx", "state" => state})
    assert redirected_to(replay_conn) =~ "/users/log_in"
    assert Phoenix.Flash.get(replay_conn.assigns.flash, :error) =~ "Failed to authenticate"
  end

  test "callback (apple) browser link restores user from state without callback session cookie",
       %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)
    oauth_orig = Application.get_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth)
    user = AccountsFixtures.user_fixture()

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    Application.put_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth,
      client_id: "com.example.web",
      client_secret: "dummy-secret"
    )

    defmodule TestExchanger.AppleLinkNoCookie do
      def exchange_apple_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"sub" => "apple-link-no-cookie", "email" => "link-no-cookie@example.com"}}
      end
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.AppleLinkNoCookie)

    on_exit(fn ->
      Application.put_env(:game_server_web, :oauth_exchanger, orig)
      Application.put_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth, oauth_orig)
    end)

    auth_conn =
      conn
      |> log_in_user(user)
      |> get("/auth/apple")

    state = oauth_state_from_redirect(auth_conn)

    callback_conn =
      post(build_conn(), "/auth/apple/callback", %{"code" => "xxx", "state" => state})

    assert redirected_to(callback_conn) =~ "/users/settings"
    assert Phoenix.Flash.get(callback_conn.assigns.flash, :error) == nil
    assert Accounts.get_user!(user.id).apple_id == "apple-link-no-cookie"
  end

  test "callback (apple) error creates session with error status", %{conn: conn} do
    orig = Application.get_env(:game_server_web, :oauth_exchanger)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    defmodule TestExchanger.ErrorApple do
      def exchange_apple_code(_code, _client_id, _secret, _redirect), do: {:error, :failed}
    end

    Application.put_env(:game_server_web, :oauth_exchanger, TestExchanger.ErrorApple)

    # Set up Apple client_secret in cache
    case :ets.info(:apple_oauth_cache) do
      :undefined -> :ets.new(:apple_oauth_cache, [:named_table, :public, :set])
      _ -> :ok
    end

    expires_at = System.system_time(:second) + 10_000

    :ets.insert(
      :apple_oauth_cache,
      {{:client_secret, "com.example.web"}, "test-secret", expires_at}
    )

    on_exit(fn ->
      Application.put_env(:game_server_web, :oauth_exchanger, orig)
      # Only delete if table exists
      case :ets.info(:apple_oauth_cache) do
        :undefined -> :ok
        _ -> :ets.delete(:apple_oauth_cache)
      end
    end)

    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "apple", status: "pending"})

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = post(conn, "/auth/apple/callback", %{"code" => "xxx", "state" => session_id})
    end)

    session = OAuthSessions.get_session(session_id)
    assert session.status == "error"
  end

  defp oauth_state_from_redirect(conn) do
    conn
    |> redirected_to()
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.fetch!("state")
  end

  test "request redirects to provider (steam)", %{conn: conn} do
    # Ueberauth Steam strategy uses Steam OpenID redirect URL
    conn = get(conn, "/auth/steam")

    # The request should redirect to Steam's OpenID path
    assert redirected_to(conn) =~ "steamcommunity.com/openid"
  end

  test "callback (steam) on error without state shows flash", %{conn: conn} do
    # Simulate Ueberauth failure assign
    failure = %{errors: [reason: :invalid]}

    conn = conn |> assign(:ueberauth_failure, failure) |> get("/auth/steam/callback")

    assert redirected_to(conn) =~ "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Failed to authenticate"
  end

  test "callback (steam) on error with state creates oauth session", %{conn: conn} do
    session_id = "session-#{System.unique_integer([:positive])}"

    failure = %{errors: [reason: :invalid]}

    # create a pending session to match API flow expectations
    OAuthSessions.create_session(session_id, %{provider: "steam", status: "pending"})

    _conn =
      conn
      |> assign(:ueberauth_failure, failure)
      |> get("/auth/steam/callback?state=#{session_id}")

    sess = OAuthSessions.get_session(session_id)
    assert sess.status == "error"
  end

  test "callback (steam) links account when user logged in", %{conn: conn} do
    # create and log in a user; get scope
    ctx = register_and_log_in_user(%{conn: conn})
    logged_conn = ctx.conn
    user = ctx.user
    scope = ctx.scope

    auth = %{uid: 777_777, info: %{nickname: "linkme", urls: %{profile: "https://steam/777777"}}}

    conn =
      logged_conn
      |> assign(:current_scope, scope)
      |> assign(:ueberauth_auth, auth)
      |> get("/auth/steam/callback")

    assert redirected_to(conn) =~ "/users/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Success."

    # Reload user and assert steam_id saved
    reloaded = GameServer.Accounts.get_user!(user.id)
    assert reloaded.steam_id == "777777"
  end

  test "callback (steam) linking conflict redirects to settings with conflict info", %{conn: conn} do
    # create an existing user that already has this steam_id
    {:ok, other} =
      GameServer.Accounts.find_or_create_from_steam(%{
        steam_id: "99999",
        display_name: "exists",
        profile_url: "https://steam/99999"
      })

    ctx = register_and_log_in_user(%{conn: conn})
    logged_conn = ctx.conn
    scope = ctx.scope

    auth = %{uid: 99_999, info: %{nickname: "conflict", urls: %{profile: "https://steam/99999"}}}

    conn =
      logged_conn
      |> assign(:current_scope, scope)
      |> assign(:ueberauth_auth, auth)
      |> get("/auth/steam/callback")

    # redirect happens to the settings page
    assert redirected_to(conn) =~ "/users/settings"

    # linking should not have overwritten the other user's steam_id or set ours
    reloaded = GameServer.Accounts.get_user!(ctx.user.id)
    assert reloaded.steam_id == nil
    other_reloaded = GameServer.Accounts.get_user!(other.id)
    assert other_reloaded.steam_id == "99999"
  end

  test "callback (steam) success browser and api flows", %{conn: conn} do
    # Simulate a successful ueaassign from Ueberauth
    auth = %{
      uid: 424_242,
      info: %{nickname: "steamuser", urls: %{profile: "https://steam/profile/424242"}}
    }

    # browser flow (no state)
    conn1 = conn |> assign(:ueberauth_auth, auth) |> get("/auth/steam/callback")
    assert redirected_to(conn1) =~ "/"

    # api flow (state) updates existing session
    session_id = "s-#{System.unique_integer([:positive])}"
    OAuthSessions.create_session(session_id, %{provider: "steam", status: "pending"})

    _conn2 =
      conn |> assign(:ueberauth_auth, auth) |> get("/auth/steam/callback?state=#{session_id}")

    session = OAuthSessions.get_session(session_id)
    assert session.status == "completed"
  end

  test "callback (steam) captures personaname from raw_info when info.name is missing", %{
    conn: conn
  } do
    # simulate raw info only (no info.name or info.nickname)
    auth = %{
      uid: 123_456,
      info: %{
        urls: %{profile: "https://steam/profile/123456"}
      },
      extra: %{
        raw_info: %{user: %{personaname: "Estar", profileurl: "https://steam/profile/123456"}}
      }
    }

    conn1 = conn |> assign(:ueberauth_auth, auth) |> get("/auth/steam/callback")

    assert redirected_to(conn1) =~ "/"

    # Reload from DB and assert display_name stored
    user = GameServer.Repo.get_by(GameServer.Accounts.User, steam_id: "123456")
    assert user != nil
    assert user.display_name == "Estar"
  end

  test "callback (steam) with state but no session is treated as browser flow", %{conn: conn} do
    auth = %{
      uid: 424_243,
      info: %{nickname: "noupstate", urls: %{profile: "https://steam/profile/424243"}}
    }

    session_id = "no-session-#{System.unique_integer([:positive])}"

    conn =
      conn |> assign(:ueberauth_auth, auth) |> get("/auth/steam/callback?state=#{session_id}")

    # Should behave like browser flow: redirect and leave no session created
    assert redirected_to(conn) =~ "/"
    assert OAuthSessions.get_session(session_id) == nil
  end

  test "GET /api/v1/auth/session/:session_id returns status, message, data at top level", %{
    conn: conn
  } do
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "google", status: "completed"})
    OAuthSessions.update_session(session_id, %{data: %{access_token: "tok", message: "done"}})

    conn = get(conn, "/api/v1/auth/session/#{session_id}")
    body = json_response(conn, 200)

    assert body["status"] == "completed"
    assert body["message"] == "done"
    assert is_map(body["data"])
    assert body["data"]["access_token"] == "tok"
    refute Map.has_key?(body["data"], "message")
  end

  test "GET /api/v1/auth/session/:session_id returns empty message and {} data when session has no data",
       %{conn: conn} do
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "google", status: "pending"})

    conn = get(conn, "/api/v1/auth/session/#{session_id}")
    body = json_response(conn, 200)

    assert body["status"] == "pending"
    assert body["message"] == ""
    assert body["data"] == %{}
  end

  test "GET /api/v1/auth/session/:session_id returns 404 error object when missing", %{conn: conn} do
    conn = get(conn, "/api/v1/auth/session/does-not-exist")
    body = json_response(conn, 404)

    assert body["error"] == "session_not_found"
    assert is_binary(body["message"])
  end
end
