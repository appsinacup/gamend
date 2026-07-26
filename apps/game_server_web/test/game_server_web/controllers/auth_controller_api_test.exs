defmodule GameServerWeb.AuthControllerApiTest do
  use GameServerWeb.ConnCase, async: false

  setup do
    # allow tests to inject a mock exchanger
    orig = Application.get_env(:game_server_web, :oauth_exchanger)
    orig_tokeninfo = Application.get_env(:game_server_core, :google_tokeninfo_client)

    on_exit(fn ->
      if is_nil(orig) do
        Application.delete_env(:game_server_web, :oauth_exchanger)
      else
        Application.put_env(:game_server_web, :oauth_exchanger, orig)
      end

      if is_nil(orig_tokeninfo) do
        Application.delete_env(:game_server_core, :google_tokeninfo_client)
      else
        Application.put_env(:game_server_core, :google_tokeninfo_client, orig_tokeninfo)
      end
    end)

    :ok
  end

  describe "GET /api/v1/auth/session/:session_id" do
    test "returns 404 for missing session id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/session/nonexistent-id")

      assert conn.status == 404
      assert json_response(conn, 404)["error"] == "session_not_found"
    end

    test "empty session path returns 400 (router)", %{conn: conn} do
      resp = get(conn, "/api/v1/auth/session/")

      assert resp.status == 400
    end
  end

  describe "GET /api/v1/auth/:provider API request" do
    test "unknown provider returns 400", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/invalid-provider")

      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "invalid_provider"
    end

    test "steam returns OpenID URL and session id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/steam")

      assert conn.status == 200

      body = json_response(conn, 200)

      assert is_binary(body["authorization_url"]) and
               String.contains?(body["authorization_url"], "steamcommunity.com/openid/login")

      assert is_binary(body["session_id"]) and byte_size(body["session_id"]) > 0

      # server should have created a pending session record
      session = GameServer.OAuthSessions.get_session(body["session_id"])
      assert session != nil
      assert session.provider == "steam"
      assert session.status == "pending"
    end

    test "API OAuth session flow stores user_id on completion (discord)", %{conn: conn} do
      # Create an API OAuth session (pending)
      resp = get(conn, ~p"/api/v1/auth/discord")
      assert resp.status == 200
      body = json_response(resp, 200)
      session_id = body["session_id"]

      # install a mock exchanger module that returns a successful discord payload
      defmodule MockExchangerDiscordOk2 do
        def exchange_discord_code(_code, _cid, _secret, _redirect),
          do:
            {:ok,
             %{
               "id" => "dX",
               "email" => "d_sess@example.com",
               "global_name" => "SessDiscord",
               "avatar" => "av"
             }}
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerDiscordOk2)

      # Simulate the provider callback for the browser flow which includes state (session_id)
      conn = post(conn, "/auth/discord/callback", %{code: "ok", state: session_id})

      # session should be completed now and include user_id in data
      status_conn = get(conn, ~p"/api/v1/auth/session/#{session_id}")
      assert status_conn.status == 200
      status_body = json_response(status_conn, 200)

      assert status_body["status"] == "completed"

      assert is_map(status_body["data"]) and is_binary(status_body["data"]["user_id"]) and
               status_body["data"]["user_id"] != ""

      # ensure user exists in DB
      assert GameServer.Repo.get(GameServer.Accounts.User, status_body["data"]["user_id"]) != nil
    end

    test "POST /api/v1/auth/:provider/callback exchanges code and returns tokens (discord)", %{
      conn: conn
    } do
      # install a mock exchanger module that returns a successful discord payload
      defmodule MockExchangerDiscordOk do
        def exchange_discord_code(_code, _cid, _secret, _redirect),
          do:
            {:ok,
             %{
               "id" => "d123",
               "email" => "d@example.com",
               "global_name" => "DiscordName",
               "avatar" => "av"
             }}
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerDiscordOk)

      conn = post(conn, "/api/v1/auth/discord/callback", %{code: "ok"})
      assert conn.status == 200
      body = json_response(conn, 200)

      assert is_binary(body["data"]["access_token"]) and is_binary(body["data"]["refresh_token"]) and
               is_integer(body["data"]["expires_in"])

      assert is_binary(body["data"]["user_id"])
    end

    test "POST /api/v1/auth/:provider/callback returns 400 on code exchange failure", %{
      conn: conn
    } do
      defmodule MockExchangerDiscordFail do
        def exchange_discord_code(_code, _cid, _sec, _r), do: {:error, :boom}
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerDiscordFail)

      ExUnit.CaptureLog.capture_log(fn ->
        conn = post(conn, "/api/v1/auth/discord/callback", %{code: "bad"})
        assert conn.status == 400
        assert json_response(conn, 400)["error"] == "exchange_failed"
      end)
    end

    test "POST /api/v1/auth/steam/callback with code (ticket) returns tokens", %{conn: conn} do
      # For API flows code is treated as the Steam auth ticket
      defmodule MockExchangerSteamTicketOk do
        def exchange_steam_ticket("valid_ticket"),
          do:
            {:ok,
             %{
               "id" => "99999",
               "display_name" => "SteamUser",
               "profile_url" => "https://steam/profile/99999"
             }}

        def exchange_steam_ticket("valid_ticket", opts) when is_list(opts) do
          if Keyword.get(opts, :fetch_profile, false) == false do
            {:ok, %{"id" => "99999"}}
          else
            exchange_steam_ticket("valid_ticket")
          end
        end

        def get_player_profile("99999"),
          do:
            {:ok,
             %{
               "id" => "99999",
               "display_name" => "SteamUser",
               "profile_url" => "https://steam/profile/99999"
             }}
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerSteamTicketOk)

      conn = post(conn, "/api/v1/auth/steam/callback", %{code: "valid_ticket"})

      assert conn.status == 200
      body = json_response(conn, 200)

      assert is_binary(body["data"]["access_token"]) and is_binary(body["data"]["refresh_token"]) and
               is_integer(body["data"]["expires_in"])

      assert is_binary(body["data"]["user_id"])
    end

    test "POST /api/v1/auth/google/callback skips profile lookup when user already has profile",
         %{conn: conn} do
      # Create existing user with google_id and display/profile set
      {:ok, _user} =
        GameServer.Accounts.find_or_create_from_google(%{
          google_id: "g1",
          display_name: "Existing",
          profile_url: "https://x",
          email: "existing@example.com"
        })

      defmodule MockExchangerGoogle do
        def exchange_google_code("valid_ticket", _cid, _sec, _redirect),
          do:
            {:ok,
             %{"id" => "g1", "email" => "g@example.com", "picture" => "pic", "name" => "Gname"}}

        def exchange_google_code("valid_ticket", _cid, _sec, _redirect, opts)
            when is_list(opts) do
          if Keyword.get(opts, :fetch_profile, false) == false do
            {:ok, %{"id" => "g1"}}
          else
            {:ok,
             %{"id" => "g1", "email" => "g@example.com", "picture" => "pic", "name" => "Gname"}}
          end
        end
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerGoogle)

      conn = post(conn, "/api/v1/auth/google/callback", %{code: "valid_ticket"})
      assert conn.status == 200
    end

    test "POST /api/v1/auth/google/callback fills missing profile fields for existing user", %{
      conn: conn
    } do
      # Create existing user with google_id but missing display_name
      {:ok, user} =
        GameServer.Accounts.find_or_create_from_google(%{
          google_id: "g2",
          email: "u2@example.com",
          display_name: nil
        })

      defmodule MockExchangerGoogleFetch do
        def exchange_google_code("valid_ticket", _cid, _sec, _redirect) do
          {:ok,
           %{
             "id" => "g2",
             "email" => "g2@example.com",
             "picture" => "https://g2",
             "name" => "FetchedG"
           }}
        end

        def exchange_google_code("valid_ticket", _cid, _sec, _redirect, opts)
            when is_list(opts) do
          if Keyword.get(opts, :fetch_profile, false) == false do
            {:ok, %{"id" => "g2"}}
          else
            {:ok,
             %{
               "id" => "g2",
               "email" => "g2@example.com",
               "picture" => "https://g2",
               "name" => "FetchedG"
             }}
          end
        end
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerGoogleFetch)

      conn = post(conn, "/api/v1/auth/google/callback", %{code: "valid_ticket"})
      assert conn.status == 200

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, user.id)
      assert reloaded.display_name == "FetchedG"
    end

    test "POST /api/v1/auth/steam/callback returns 400 when verification fails", %{conn: conn} do
      defmodule MockExchangerSteamFail do
        def exchange_steam_ticket(_code), do: {:error, :invalid}

        def exchange_steam_ticket(_code, _opts), do: {:error, :invalid}
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerSteamFail)

      ExUnit.CaptureLog.capture_log(fn ->
        conn = post(conn, "/api/v1/auth/steam/callback", %{code: "bad_ticket"})
        assert conn.status == 400
        assert json_response(conn, 400)["error"] == "exchange_failed"
      end)
    end

    test "POST /api/v1/auth/apple/callback skips profile lookup when user already has profile", %{
      conn: conn
    } do
      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_client_id,
        "com.example.web"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_client_id
        )
      end)

      {:ok, _user} =
        GameServer.Accounts.find_or_create_from_apple(%{
          apple_id: "a1",
          display_name: "Existing",
          profile_url: "https://x",
          email: "existing@apple.com"
        })

      # ensure Apple client secret generation doesn't fail in tests
      System.put_env(
        "APPLE_PRIVATE_KEY",
        "-----BEGIN PRIVATE KEY-----\nMYSAMPLE\n-----END PRIVATE KEY-----"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_private_key
        )
      end)

      defmodule MockExchangerApple do
        def exchange_apple_code("valid_ticket", _cid, _secret, _redirect) do
          {:ok, %{"sub" => "a1", "email" => "a@example.com", "name" => "Aname"}}
        end

        def exchange_apple_code("valid_ticket", _cid, _secret, _redirect, opts)
            when is_list(opts) do
          if Keyword.get(opts, :fetch_profile, false) == false do
            {:ok, %{"sub" => "a1"}}
          else
            {:ok, %{"sub" => "a1", "email" => "a@example.com", "name" => "Aname"}}
          end
        end
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerApple)

      conn = post(conn, "/api/v1/auth/apple/callback", %{code: "valid_ticket"})
      assert conn.status == 200
    end

    test "POST /api/v1/auth/apple/callback fetches profile when missing fields", %{conn: conn} do
      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_client_id,
        "com.example.web"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_client_id
        )
      end)

      {:ok, user} =
        GameServer.Accounts.find_or_create_from_apple(%{apple_id: "a2", display_name: nil})

      # ensure Apple client secret generation doesn't fail in tests
      System.put_env(
        "APPLE_PRIVATE_KEY",
        "-----BEGIN PRIVATE KEY-----\nMYSAMPLE\n-----END PRIVATE KEY-----"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_private_key
        )
      end)

      defmodule MockExchangerAppleFetch do
        def exchange_apple_code("valid_ticket", _cid, _secret, _redirect) do
          {:ok, %{"sub" => "a2", "email" => "a2@example.com", "name" => "FetchedA"}}
        end

        def exchange_apple_code("valid_ticket", _cid, _secret, _redirect, opts)
            when is_list(opts) do
          if Keyword.get(opts, :fetch_profile, false) == false do
            {:ok, %{"sub" => "a2"}}
          else
            {:ok, %{"sub" => "a2", "email" => "a2@example.com", "name" => "FetchedA"}}
          end
        end
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerAppleFetch)

      conn = post(conn, "/api/v1/auth/apple/callback", %{code: "valid_ticket"})
      assert conn.status == 200

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, user.id)
      assert reloaded.display_name == "FetchedA"
    end

    test "POST /api/v1/auth/apple/callback uses APPLE_WEB_CLIENT_ID when set", %{conn: conn} do
      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_client_id,
        "com.example.web"
      )

      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_ios_client_id,
        "com.example.ios"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_client_id
        )

        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_ios_client_id
        )
      end)

      defmodule MockExchangerAppleClientId do
        def exchange_apple_code("valid_ticket", cid, _secret, _redirect) do
          send(self(), {:apple_client_id, cid})
          {:ok, %{"sub" => "a_web"}}
        end

        def exchange_apple_code("valid_ticket", cid, _secret, _redirect, _opts) do
          send(self(), {:apple_client_id, cid})
          {:ok, %{"sub" => "a_web"}}
        end
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerAppleClientId)

      conn = post(conn, "/api/v1/auth/apple/callback", %{code: "valid_ticket"})
      assert conn.status == 200
      assert_received {:apple_client_id, "com.example.web"}
    end

    test "POST /api/v1/auth/apple/ios/callback uses GAMEND_OAUTH_APPLE_IOS_CLIENT_ID when set", %{
      conn: conn
    } do
      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_client_id,
        "com.example.web"
      )

      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_ios_client_id,
        "com.example.ios"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_client_id
        )

        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :apple_ios_client_id
        )
      end)

      defmodule MockExchangerAppleIosClientId do
        def exchange_apple_code("valid_ticket", cid, _secret, _redirect) do
          send(self(), {:apple_ios_client_id, cid})
          {:ok, %{"sub" => "a_ios"}}
        end

        def exchange_apple_code("valid_ticket", cid, _secret, _redirect, _opts) do
          send(self(), {:apple_ios_client_id, cid})
          {:ok, %{"sub" => "a_ios"}}
        end
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerAppleIosClientId)

      conn = post(conn, "/api/v1/auth/apple/ios/callback", %{code: "valid_ticket"})
      assert conn.status == 200
      assert_received {:apple_ios_client_id, "com.example.ios"}
    end

    test "POST /api/v1/auth/steam/callback skips profile lookup when user already has profile", %{
      conn: conn
    } do
      # Create existing user that already has display_name and profile_url
      {:ok, existing} =
        GameServer.Accounts.find_or_create_from_steam(%{
          steam_id: "99999",
          display_name: "Existing",
          profile_url: "https://x"
        })

      defmodule MockExchangerSteamIdOnlyNoProfile do
        def exchange_steam_ticket("valid_ticket", _opts) do
          {:ok,
           %{
             "id" => "99999",
             "display_name" => "SteamUser",
             "profile_url" => "https://steam/profile/99999"
           }}
        end

        def get_player_profile(_steamid),
          do:
            {:ok,
             %{
               "id" => "99999",
               "display_name" => "SteamUser",
               "profile_url" => "https://steam/profile/99999"
             }}
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerSteamIdOnlyNoProfile)

      conn = post(conn, "/api/v1/auth/steam/callback", %{code: "valid_ticket"})
      assert conn.status == 200
      body = json_response(conn, 200)

      assert is_binary(body["data"]["access_token"]) and is_binary(body["data"]["refresh_token"]) and
               is_integer(body["data"]["expires_in"])

      assert is_binary(body["data"]["user_id"])
    end

    test "POST /api/v1/auth/steam/callback fills missing profile fields for existing user", %{
      conn: conn
    } do
      # Create existing user with missing display_name to force fetching
      {:ok, existing} =
        GameServer.Accounts.find_or_create_from_steam(%{steam_id: "99999", display_name: nil})

      defmodule MockExchangerSteamIdOnlyWithProfile do
        def exchange_steam_ticket("valid_ticket", _opts) do
          {:ok,
           %{
             "id" => "99999",
             "display_name" => "FetchedName",
             "profile_url" => "https://steam/profile/99999"
           }}
        end

        def get_player_profile("99999") do
          {:ok,
           %{
             "id" => "99999",
             "display_name" => "FetchedName",
             "profile_url" => "https://steam/profile/99999"
           }}
        end
      end

      Application.put_env(:game_server_web, :oauth_exchanger, MockExchangerSteamIdOnlyWithProfile)

      conn = post(conn, "/api/v1/auth/steam/callback", %{code: "valid_ticket"})
      assert conn.status == 200

      # ensure user got updated with display_name
      reloaded = GameServer.Repo.get(GameServer.Accounts.User, existing.id)
      assert reloaded.display_name == "FetchedName"
    end

    # Note: API now expects 'code' to be a Steam auth ticket. Supplying a steam id is not allowed.
  end

  describe "POST /api/v1/auth/google/id_token" do
    test "returns tokens for valid id_token", %{conn: conn} do
      defmodule MockGoogleTokeninfoOk do
        def get(_url, opts) do
          params = Keyword.get(opts, :params, %{})
          token = Map.get(params, :id_token) || Map.get(params, "id_token")

          if token == "good" do
            {:ok,
             %{
               status: 200,
               body: %{
                 "sub" => "gsub_1",
                 "aud" => "webcid",
                 "iss" => "https://accounts.google.com",
                 "email" => "g@example.com",
                 "name" => "G User",
                 "picture" => "https://pic",
                 "expires_in" => "3600"
               }
             }}
          else
            {:ok, %{status: 400, body: %{"error" => "invalid_token"}}}
          end
        end
      end

      Application.put_env(:game_server_core, :google_tokeninfo_client, MockGoogleTokeninfoOk)

      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :google_web_client_id,
        "webcid"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :google_web_client_id
        )
      end)

      conn = post(conn, "/api/v1/auth/google/id_token", %{id_token: "good"})
      assert conn.status == 200
      body = json_response(conn, 200)

      assert is_binary(body["data"]["access_token"])
      assert is_binary(body["data"]["refresh_token"])
      assert is_integer(body["data"]["expires_in"])
      assert is_binary(body["data"]["user_id"])

      user = GameServer.Repo.get(GameServer.Accounts.User, body["data"]["user_id"])
      assert user != nil
      assert user.google_id == "gsub_1"
    end

    test "returns 400 when aud does not match", %{conn: conn} do
      defmodule MockGoogleTokeninfoBadAud do
        def get(_url, _opts) do
          {:ok,
           %{
             status: 200,
             body: %{
               "sub" => "gsub_2",
               "aud" => "some_other_client",
               "iss" => "https://accounts.google.com",
               "expires_in" => "3600"
             }
           }}
        end
      end

      Application.put_env(:game_server_core, :google_tokeninfo_client, MockGoogleTokeninfoBadAud)

      GameServer.SettingsHelpers.put(
        :game_server_core,
        GameServer.OAuth.Providers,
        :google_web_client_id,
        "webcid"
      )

      on_exit(fn ->
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.OAuth.Providers,
          :google_web_client_id
        )
      end)

      conn = post(conn, "/api/v1/auth/google/id_token", %{id_token: "good"})
      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "invalid_token"
    end

    test "returns 400 when id_token missing", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/google/id_token", %{})
      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "missing_param"
    end
  end
end
