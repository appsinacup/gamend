defmodule GamendWeb.Api.V1.ProviderLinkTest do
  # Signing in and linking through a provider are separate endpoints: a
  # bearer token never turns a sign-in into a link. Every answer here also
  # passes `GamendWeb.ResponseContract`.
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.OAuthSessions
  alias Gamend.SettingsHelpers
  alias GamendWeb.Auth.Guardian

  defmodule Exchanger do
    # "d-<id>" is a Discord code for the Discord account <id>; anything else
    # is refused. A Steam ticket "t-<id>" is the Steam account <id>.
    def exchange_discord_code("d-" <> id, _cid, _secret, _redirect),
      do: {:ok, %{"id" => id, "email" => "#{id}@discord.test", "global_name" => "D #{id}"}}

    def exchange_discord_code(_code, _cid, _secret, _redirect), do: {:error, :bad_code}

    def exchange_steam_ticket("t-" <> id, _opts), do: {:ok, %{"id" => id, "display_name" => "S"}}
    def exchange_steam_ticket(_ticket, _opts), do: {:error, :invalid_ticket}

    def exchange_apple_code("a-" <> id, _cid, _secret, _redirect), do: {:ok, %{"sub" => id}}
  end

  defmodule Tokeninfo do
    def get(_url, opts) do
      case Map.get(Keyword.get(opts, :params, %{}), :id_token) do
        "g-" <> id ->
          {:ok,
           %{
             status: 200,
             body: %{
               "sub" => id,
               "aud" => "webcid",
               "iss" => "https://accounts.google.com",
               "email" => "#{id}@google.test",
               "expires_in" => "3600"
             }
           }}

        _ ->
          {:ok, %{status: 400, body: %{"error" => "invalid_token"}}}
      end
    end
  end

  setup %{conn: conn} do
    for key <- [:discord_client_id, :google_client_id, :apple_client_id, :steam_api_key] do
      SettingsHelpers.put(:gamend_core, Gamend.OAuth.Providers, key, "test-#{key}")
    end

    SettingsHelpers.put(:gamend_core, Gamend.OAuth.Providers, :google_web_client_id, "webcid")
    SettingsHelpers.put(:gamend_core, Gamend.OAuth.Providers, :apple_ios_client_id, "ios")
    Application.put_env(:gamend_web, :oauth_exchanger, Exchanger)
    Application.put_env(:gamend_core, :google_tokeninfo_client, Tokeninfo)

    on_exit(fn ->
      for key <- [
            :discord_client_id,
            :google_client_id,
            :apple_client_id,
            :steam_api_key,
            :google_web_client_id,
            :apple_ios_client_id
          ] do
        SettingsHelpers.delete(:gamend_core, Gamend.OAuth.Providers, key)
      end

      Application.delete_env(:gamend_web, :oauth_exchanger)
      Application.delete_env(:gamend_core, :google_tokeninfo_client)
    end)

    user = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    %{user: user, anon: conn, conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  describe "sign-in" do
    test "a bearer token does not turn it into a link", ctx do
      body =
        ctx.conn |> post("/api/v1/auth/discord/callback", %{code: "d-1"}) |> json_response(200)

      # The same Session as email login, for the Discord account.
      assert %{"user_id" => signed_in, "username" => "" <> _, "display_name" => "D 1"} =
               body["data"]

      refute signed_in == ctx.user.id
      assert Accounts.get_user!(ctx.user.id).discord_id == nil
    end

    test "a missing code is validation_failed", ctx do
      resp = ctx.anon |> post("/api/v1/auth/discord/callback", %{}) |> json_response(422)
      assert resp["error"] == "validation_failed"
    end
  end

  describe "link with a code" do
    test "links to the signed-in account and answers it", ctx do
      body =
        ctx.conn |> post("/api/v1/me/providers/discord", %{code: "d-2"}) |> json_response(200)

      assert body["data"]["id"] == ctx.user.id
      assert body["data"]["linked_providers"]["discord"]
      assert Accounts.get_user!(ctx.user.id).discord_id == "2"
    end

    test "a Steam ticket links Steam", ctx do
      body = ctx.conn |> post("/api/v1/me/providers/steam", %{code: "t-7"}) |> json_response(200)
      assert body["data"]["linked_providers"]["steam"]

      resp = ctx.conn |> post("/api/v1/me/providers/steam", %{}) |> json_response(422)
      assert resp["error"] == "validation_failed"
    end

    test "an account already linked elsewhere is a conflict", ctx do
      {:ok, _other} =
        Accounts.find_or_create_from_discord(%{
          discord_id: "3",
          email: "3@discord.test",
          email_verified: true
        })

      resp =
        ctx.conn |> post("/api/v1/me/providers/discord", %{code: "d-3"}) |> json_response(409)

      assert resp["error"] == "provider_already_linked"
    end

    test "a refused code, an unknown provider, and no token", ctx do
      resp =
        ctx.conn |> post("/api/v1/me/providers/discord", %{code: "nope"}) |> json_response(400)

      assert resp["error"] == "exchange_failed"

      # Not one of the path's documented providers: a URL that names nothing.
      resp = ctx.conn |> post("/api/v1/me/providers/myspace", %{code: "x"}) |> json_response(404)
      assert resp["error"] == "not_found"

      assert ctx.anon
             |> post("/api/v1/me/providers/discord", %{code: "d-4"})
             |> json_response(401)
    end
  end

  test "link with a Google ID token and a native Apple code", ctx do
    body =
      ctx.conn
      |> post("/api/v1/me/providers/google/id_token", %{id_token: "g-5"})
      |> json_response(200)

    assert body["data"]["linked_providers"]["google"]

    body =
      ctx.conn |> post("/api/v1/me/providers/apple/ios", %{code: "a-6"}) |> json_response(200)

    assert body["data"]["linked_providers"]["apple"]
    user = Accounts.get_user!(ctx.user.id)
    assert {user.google_id, user.apple_id} == {"5", "6"}
  end

  describe "link through the provider's page" do
    test "the session links, and only its owner polls it", ctx do
      started =
        ctx.conn |> post("/api/v1/me/providers/discord/authorize") |> json_response(200)

      assert %{"authorization_url" => "https://discord.com/" <> _, "session_id" => session_id} =
               started["data"]

      pending =
        ctx.conn |> get("/api/v1/me/providers/sessions/#{session_id}") |> json_response(200)

      assert pending["data"] == %{
               "status" => "pending",
               "error" => "",
               "message" => "",
               "provider" => "discord"
             }

      # The player finishes at Discord, which sends the browser back.
      post(ctx.anon, "/auth/discord/callback", %{code: "d-8", state: session_id})

      done = ctx.conn |> get("/api/v1/me/providers/sessions/#{session_id}") |> json_response(200)
      assert done["data"]["status"] == "completed"
      assert Accounts.get_user!(ctx.user.id).discord_id == "8"

      # Not someone else's, and not the sign-in poll's.
      other = AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(other)

      ctx.anon
      |> put_req_header("authorization", "Bearer " <> token)
      |> get("/api/v1/me/providers/sessions/#{session_id}")
      |> json_response(404)

      ctx.anon |> get("/api/v1/auth/session/#{session_id}") |> json_response(404)
    end

    test "a conflict ends the session with its code", ctx do
      {:ok, _other} =
        Accounts.find_or_create_from_discord(%{
          discord_id: "9",
          email: "9@discord.test",
          email_verified: true
        })

      started =
        ctx.conn |> post("/api/v1/me/providers/discord/authorize") |> json_response(200)

      session_id = started["data"]["session_id"]
      post(ctx.anon, "/auth/discord/callback", %{code: "d-9", state: session_id})

      done = ctx.conn |> get("/api/v1/me/providers/sessions/#{session_id}") |> json_response(200)
      assert %{"status" => "error", "error" => "provider_already_linked"} = done["data"]
    end

    test "a sign-in session started with a token still signs in", ctx do
      started = ctx.conn |> get("/api/v1/auth/discord") |> json_response(200)
      session_id = started["data"]["session_id"]
      refute Map.has_key?(OAuthSessions.get_session(session_id).data, "link_user_id")

      post(ctx.anon, "/auth/discord/callback", %{code: "d-10", state: session_id})

      body = ctx.anon |> get("/api/v1/auth/session/#{session_id}") |> json_response(200)
      assert body["data"]["session"]["user_id"] != ctx.user.id
      assert Accounts.get_user!(ctx.user.id).discord_id == nil
    end
  end

  test "unlinking and the device answer the current user", ctx do
    # The last provider cannot be unlinked, so there are two.
    ctx.conn |> post("/api/v1/me/providers/discord", %{code: "d-11"}) |> json_response(200)
    ctx.conn |> post("/api/v1/me/providers/steam", %{code: "t-11"}) |> json_response(200)

    body = ctx.conn |> post("/api/v1/me/device", %{device_id: "dev-11"}) |> json_response(200)
    assert body["data"]["linked_providers"]["device"]

    body = ctx.conn |> delete("/api/v1/me/providers/discord") |> json_response(200)
    refute body["data"]["linked_providers"]["discord"]

    body = ctx.conn |> delete("/api/v1/me/device") |> json_response(200)
    refute body["data"]["linked_providers"]["device"]
  end
end
