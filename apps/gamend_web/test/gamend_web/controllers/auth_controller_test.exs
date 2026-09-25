defmodule GamendWeb.AuthControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.OAuthSessions
  alias Gamend.SettingsHelpers

  defp put_provider_setting(key, value) do
    orig = SettingsHelpers.get(:gamend_core, Gamend.OAuth.Providers, key)
    SettingsHelpers.put(:gamend_core, Gamend.OAuth.Providers, key, value)

    on_exit(fn ->
      SettingsHelpers.put(:gamend_core, Gamend.OAuth.Providers, key, orig)
    end)
  end

  # Provider routes 404 unless the provider is configured; the tests below
  # assume these are.
  setup do
    put_provider_setting(:discord_client_id, "test-discord-id")
    put_provider_setting(:google_client_id, "test-google-id")
    put_provider_setting(:facebook_client_id, "test-facebook-id")
    put_provider_setting(:github_client_id, "test-github-id")
    put_provider_setting(:steam_api_key, "test-steam-key")
    :ok
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

  # No scope: a GitHub App ignores it, its permissions live on the App.
  test "request redirects to provider (github)", %{conn: conn} do
    put_provider_setting(:github_client_id, "gh-123")

    conn = get(conn, "/auth/github")
    assert redirected_to(conn) =~ "github.com/login/oauth/authorize"
    assert redirected_to(conn) =~ "client_id=gh-123"
    refute redirected_to(conn) =~ "scope="
  end

  test "request redirects to provider (apple)", %{conn: conn} do
    put_provider_setting(:apple_client_id, "apple-123")

    conn = get(conn, "/auth/apple")
    assert redirected_to(conn) =~ "appleid.apple.com"
    assert redirected_to(conn) =~ "client_id=apple-123"
  end

  test "callback (discord) on error with state creates oauth session", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    defmodule TestExchanger do
      def exchange_discord_code(_code, _client_id, _secret, _redirect), do: {:error, :boom}
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

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
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    defmodule TestExchanger.ErrorDiscord do
      def exchange_discord_code(_code, _client_id, _secret, _redirect), do: {:error, :boom}
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.ErrorDiscord)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/discord/callback?code=abc")
    end)

    conn = get(conn, "/auth/discord/callback?code=abc")
    assert redirected_to(conn) =~ "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Failed to authenticate"
  end

  test "callback with neither code nor state logs a warning, not an error", %{conn: conn} do
    # A reloaded or bookmarked callback URL, or a crawler following one: the
    # user's dead end, not a server fault, so it must not inflate the error
    # count on the admin Logs page.
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        conn = post(conn, "/auth/google/callback", %{})
        assert redirected_to(conn) =~ "log_in"
      end)

    assert log =~ "[warning]"
    assert log =~ "OAuth callback with invalid params"
    refute log =~ "[error]"
  end

  test "callback (discord) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    defmodule TestExchanger.SuccessDiscord do
      def exchange_discord_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"id" => "d123", "email" => "d@example.com", "username" => "duser"}}
      end
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.SuccessDiscord)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

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

  describe "an account scheduled for deletion" do
    defmodule TestExchanger.ScheduledDiscord do
      def exchange_discord_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"id" => "d-scheduled", "email" => "leaving@example.com", "username" => "leaving"}}
      end
    end

    setup do
      orig = Application.get_env(:gamend_web, :oauth_exchanger)
      Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.ScheduledDiscord)
      SettingsHelpers.put(:gamend_core, Accounts, :deletion_grace_days, 30)

      on_exit(fn ->
        Application.put_env(:gamend_web, :oauth_exchanger, orig)
        SettingsHelpers.delete(:gamend_core, Accounts, :deletion_grace_days)
      end)

      {:ok, user} =
        Accounts.find_or_create_from_discord(%{
          discord_id: "d-scheduled",
          email: "leaving@example.com"
        })

      {:ok, {:scheduled, user, _}} = Accounts.request_deletion(user)
      %{user: user}
    end

    test "the polling flow answers deletion_scheduled and issues no tokens",
         %{conn: conn, user: user} do
      session_id = "sid-#{System.unique_integer([:positive])}"
      OAuthSessions.create_session(session_id, %{provider: "discord", status: "pending"})

      _conn = get(conn, "/auth/discord/callback?code=abc&state=#{session_id}")

      session = OAuthSessions.get_session(session_id)
      assert session.status == "error"
      assert session.data["error"] == "deletion_scheduled"
      refute Map.has_key?(session.data, "access_token")
      assert Accounts.deletion_scheduled?(Accounts.get_user!(user.id))
    end

    test "signing in with the provider on the website keeps the account",
         %{conn: conn, user: user} do
      # A browser flow's state, as the request step issues it.
      state = "browser:#{System.unique_integer([:positive])}"
      OAuthSessions.create_session(state, %{provider: "discord", status: "pending"})

      conn = get(conn, "/auth/discord/callback?code=abc&state=#{state}")

      assert get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "will not be deleted"
      refute Accounts.deletion_scheduled?(Accounts.get_user!(user.id))
    end
  end

  test "callback (google) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

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

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.SuccessGoogle)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

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
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    defmodule TestExchanger.ErrorGoogle do
      def exchange_google_code(_code, _client_id, _secret, _redirect), do: {:error, :failed}
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.ErrorGoogle)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "google", status: "pending"})

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/google/callback?code=xxx&state=#{session_id}")
    end)

    session = OAuthSessions.get_session(session_id)
    assert session.status == "error"
  end

  test "callback (facebook) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

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

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.SuccessFacebook)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

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
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    defmodule TestExchanger.ErrorFacebook do
      def exchange_facebook_code(_code, _client_id, _secret, _redirect), do: {:error, :failed}
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.ErrorFacebook)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "facebook", status: "pending"})

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/facebook/callback?code=yyy&state=#{session_id}")
    end)

    session = OAuthSessions.get_session(session_id)
    assert session.status == "error"
  end

  test "callback (github) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    defmodule TestExchanger.SuccessGithub do
      def exchange_github_code(_code, _client_id, _secret, _redirect) do
        {:ok,
         %{
           "id" => 583_231,
           "login" => "octocat",
           "name" => "The Octocat",
           "avatar_url" => "https://avatars.githubusercontent.com/u/583231",
           "email" => "octocat@example.com",
           "email_verified" => true
         }}
      end
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.SuccessGithub)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

    # browser flow, with the state /auth/github issued
    auth_conn = get(conn, "/auth/github")
    state = oauth_state_from_redirect(auth_conn)

    conn1 = get(build_conn(), "/auth/github/callback?code=yyy&state=#{state}")
    assert redirected_to(conn1) == "/"
    assert Phoenix.Flash.get(conn1.assigns.flash, :error) == nil

    # GitHub's integer id is stored as a string
    user = Accounts.get_user_by_github_id("583231")
    assert user.email == "octocat@example.com"
    assert user.display_name == "The Octocat"
    assert user.profile_url == "https://avatars.githubusercontent.com/u/583231"

    # api flow with state
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "github", status: "pending"})

    _conn2 = get(conn, "/auth/github/callback?code=yyy&state=#{session_id}")

    session = OAuthSessions.get_session(session_id)
    assert session.status == "completed"
  end

  test "callback (github) error creates session with error status", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    defmodule TestExchanger.ErrorGithub do
      def exchange_github_code(_code, _client_id, _secret, _redirect), do: {:error, :failed}
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.ErrorGithub)

    on_exit(fn -> Application.put_env(:gamend_web, :oauth_exchanger, orig) end)

    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "github", status: "pending"})

    ExUnit.CaptureLog.capture_log(fn ->
      _conn = get(conn, "/auth/github/callback?code=yyy&state=#{session_id}")
    end)

    session = OAuthSessions.get_session(session_id)
    assert session.status == "error"
  end

  test "callback (apple) success browser and api flows", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    defmodule TestExchanger.SuccessApple do
      def exchange_apple_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"sub" => "apple123", "email" => "apple@example.com"}}
      end
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.SuccessApple)

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
      Application.put_env(:gamend_web, :oauth_exchanger, orig)
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

  # Apple sends the name once, as a `user` form field beside the code, and
  # never in the ID token: a callback that ignores it leaves the account
  # nameless for good.
  test "callback (apple) takes the display name from the one-time user field", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)
    oauth_orig = Application.get_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth)

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    Application.put_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth,
      client_id: "com.example.web",
      client_secret: "dummy-secret"
    )

    defmodule TestExchanger.AppleWithName do
      def exchange_apple_code(_code, _client_id, _secret, _redirect) do
        {:ok, %{"sub" => "apple-with-name", "email" => "apple-with-name@example.com"}}
      end
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.AppleWithName)

    on_exit(fn ->
      Application.put_env(:gamend_web, :oauth_exchanger, orig)
      Application.put_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth, oauth_orig)
    end)

    state = oauth_state_from_redirect(get(conn, "/auth/apple"))
    user = ~s({"name":{"firstName":" Ada ","lastName":"Lovelace"},"email":"x@y.z"})

    conn =
      post(build_conn(), "/auth/apple/callback", %{
        "code" => "xxx",
        "state" => state,
        "user" => user
      })

    assert redirected_to(conn) == "/"
    assert Accounts.get_user_by_apple_id("apple-with-name").display_name == "Ada Lovelace"
  end

  test "callback (apple) browser form_post works without callback session cookie", %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)
    oauth_orig = Application.get_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth)

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.OAuth.Providers,
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

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.AppleNoCookie)

    on_exit(fn ->
      Application.put_env(:gamend_web, :oauth_exchanger, orig)
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

    # A replay is almost always a reader pressing back on a sign-in that
    # already worked, so it is not told authentication failed. The state stays
    # spent either way — that is what makes it single-use.
    assert Phoenix.Flash.get(replay_conn.assigns.flash, :error) == nil
    assert OAuthSessions.get_session(state).status == "completed"
  end

  test "callback (apple) browser link restores user from state without callback session cookie",
       %{conn: conn} do
    orig = Application.get_env(:gamend_web, :oauth_exchanger)
    oauth_orig = Application.get_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth)
    user = AccountsFixtures.user_fixture()

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.OAuth.Providers,
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

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.AppleLinkNoCookie)

    on_exit(fn ->
      Application.put_env(:gamend_web, :oauth_exchanger, orig)
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
    orig = Application.get_env(:gamend_web, :oauth_exchanger)

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    defmodule TestExchanger.ErrorApple do
      def exchange_apple_code(_code, _client_id, _secret, _redirect), do: {:error, :failed}
    end

    Application.put_env(:gamend_web, :oauth_exchanger, TestExchanger.ErrorApple)

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
      Application.put_env(:gamend_web, :oauth_exchanger, orig)
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
    reloaded = Gamend.Accounts.get_user!(user.id)
    assert reloaded.steam_id == "777777"
  end

  test "callback (steam) linking conflict redirects to settings with conflict info", %{conn: conn} do
    # create an existing user that already has this steam_id
    {:ok, other} =
      Gamend.Accounts.find_or_create_from_steam(%{
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
    reloaded = Gamend.Accounts.get_user!(ctx.user.id)
    assert reloaded.steam_id == nil
    other_reloaded = Gamend.Accounts.get_user!(other.id)
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
    user = Gamend.Repo.get_by(Gamend.Accounts.User, steam_id: "123456")
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

  test "GET /api/v1/auth/session/:session_id hands the session over once", %{conn: conn} do
    user = Gamend.AccountsFixtures.user_fixture()
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "google", status: "completed"})

    OAuthSessions.update_session(session_id, %{
      data: %{
        access_token: "tok",
        refresh_token: "ref",
        expires_in: 900,
        user_id: user.id,
        username: user.username,
        display_name: "",
        message: "done"
      }
    })

    body = conn |> get("/api/v1/auth/session/#{session_id}") |> json_response(200)
    data = body["data"]

    assert data["status"] == "completed"
    assert data["message"] == "done"
    assert data["error"] == ""
    assert data["session"]["access_token"] == "tok"
    assert data["session"]["user_id"] == user.id
    assert data["session"]["username"] == user.username

    again = conn |> get("/api/v1/auth/session/#{session_id}") |> json_response(200)
    assert again["data"]["status"] == "completed"
    assert again["data"]["session"] == nil
  end

  test "GET /api/v1/auth/session/:session_id is pending with no session yet", %{conn: conn} do
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{provider: "google", status: "pending"})

    body = conn |> get("/api/v1/auth/session/#{session_id}") |> json_response(200)

    assert body["data"] == %{
             "status" => "pending",
             "error" => "",
             "message" => "",
             "session" => nil
           }
  end

  test "GET /api/v1/auth/session/:session_id reports a failed sign-in by code", %{conn: conn} do
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{
      provider: "google",
      status: "error",
      data: %{error: "account_not_activated", message: "Pending activation"}
    })

    body = conn |> get("/api/v1/auth/session/#{session_id}") |> json_response(200)

    assert %{"status" => "error", "error" => "account_not_activated", "session" => nil} =
             body["data"]
  end

  test "GET /api/v1/auth/session/:session_id does not show a link session", %{conn: conn} do
    user = Gamend.AccountsFixtures.user_fixture()
    session_id = "sid-#{System.unique_integer([:positive])}"

    OAuthSessions.create_session(session_id, %{
      provider: "google",
      status: "completed",
      data: %{link_user_id: user.id, provider: "google"}
    })

    body = conn |> get("/api/v1/auth/session/#{session_id}") |> json_response(404)
    assert body["error"] == "session_not_found"
  end

  test "GET /api/v1/auth/session/:session_id returns 404 error object when missing", %{conn: conn} do
    conn = get(conn, "/api/v1/auth/session/does-not-exist")
    body = json_response(conn, 404)

    assert body["error"] == "session_not_found"
    assert is_binary(body["message"])
  end
end
