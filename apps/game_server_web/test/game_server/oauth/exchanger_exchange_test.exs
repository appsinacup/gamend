defmodule GameServer.OAuth.ExchangerExchangeTest do
  use ExUnit.Case, async: false

  alias GameServer.OAuth.Exchanger

  # Define a small test client we can inject via application env. Placing this
  # at top-level ensures the module is compiled once and avoids repeated
  # "redefining module" warnings that happen when defmodule is evaluated in
  # setup blocks multiple times.
  defmodule TestClient do
    # Group all post/2 clauses together
    def post("https://discord.com/api/oauth2/token", opts) do
      case opts[:form] do
        %{code: "ok_code"} -> {:ok, %{status: 200, body: %{"access_token" => "d_token"}}}
        _ -> {:error, :bad_request}
      end
    end

    def post("https://oauth2.googleapis.com/token", opts) do
      case opts[:form] do
        %{code: "ok_code"} -> {:ok, %{status: 200, body: %{"access_token" => "g_token"}}}
        _ -> {:ok, %{status: 400, body: %{}}}
      end
    end

    def post("https://appleid.apple.com/auth/token", opts) do
      case opts[:form] do
        %{code: "ok_code"} ->
          id_token =
            apple_token(%{
              "sub" => "a1",
              "email" => "a@example.com",
              "iss" => "https://appleid.apple.com",
              "aud" => "cid",
              "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix()
            })

          {:ok, %{status: 200, body: %{"id_token" => id_token}}}

        _ ->
          {:ok, %{status: 400, body: %{}}}
      end
    end

    def post("https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/", opts) do
      case opts[:form] do
        %{ticket: "valid_ticket", appid: _, key: _} ->
          {:ok,
           %{
             status: 200,
             body: %{"response" => %{"params" => %{"ownersteamid" => "99999"}, "result" => "OK"}}
           }}

        _ ->
          {:ok, %{status: 200, body: %{"response" => %{"result" => "Fail"}}}}
      end
    end

    # Group all get/2 clauses together
    def get("https://discord.com/api/users/@me", opts) do
      case opts[:headers] do
        [{"Authorization", "Bearer d_token"}] ->
          {:ok, %{status: 200, body: %{"id" => "d1", "email" => "d@example.com"}}}

        _ ->
          {:error, :bad}
      end
    end

    def get("https://www.googleapis.com/oauth2/v2/userinfo", opts) do
      case opts[:headers] do
        [{"Authorization", "Bearer g_token"}] ->
          {:ok, %{status: 200, body: %{"id" => "g1", "email" => "g@example.com"}}}

        _ ->
          {:error, :bad}
      end
    end

    def get("https://graph.facebook.com/v18.0/oauth/access_token", opts) do
      case opts[:params] do
        %{code: "ok_code"} -> {:ok, %{status: 200, body: %{"access_token" => "f_token"}}}
        _ -> {:ok, %{status: 500, body: ""}}
      end
    end

    def get("https://graph.facebook.com/v18.0/me", opts) do
      case opts[:params] do
        %{access_token: "f_token"} ->
          {:ok, %{status: 200, body: %{"id" => "f1", "email" => "f@example.com"}}}

        _ ->
          {:error, :bad}
      end
    end

    def get("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/", opts) do
      case opts[:params] do
        %{steamids: "12345"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "response" => %{
                 "players" => [
                   %{
                     "steamid" => "12345",
                     "personaname" => "steam_user",
                     "profileurl" => "https://steam/profile/12345",
                     "avatarfull" => "https://steam/avatar/12345_full.jpg"
                   }
                 ]
               }
             }
           }}

        %{steamids: "99999"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "response" => %{
                 "players" => [
                   %{
                     "steamid" => "99999",
                     "personaname" => "steam_ticket_user",
                     "profileurl" => "https://steam/profile/99999",
                     "avatarfull" => "https://steam/avatar/99999_full.jpg"
                   }
                 ]
               }
             }
           }}

        _ ->
          {:ok, %{status: 200, body: %{"response" => %{"players" => []}}}}
      end
    end

    def get("https://appleid.apple.com/auth/keys") do
      jwk = Application.fetch_env!(:game_server_core, :apple_test_jwk)
      {_, public_jwk} = JOSE.JWK.to_public_map(jwk)

      {:ok,
       %{
         status: 200,
         body: %{"keys" => [Map.merge(public_jwk, %{"kid" => "test-key", "alg" => "RS256"})]}
       }}
    end

    # steam ticket POST handler moved to the grouped post/2 section

    defp apple_token(claims) do
      Application.fetch_env!(:game_server_core, :apple_test_jwk)
      |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "test-key"}, claims)
      |> JOSE.JWS.compact()
      |> elem(1)
    end
  end

  setup do
    Application.put_env(:game_server_core, :apple_test_jwk, JOSE.JWK.generate_key({:rsa, 2048}))
    Application.put_env(:game_server_core, :oauth_exchanger_client, TestClient)
    # Ensure a test steam api key and app id are available
    Application.put_env(:ueberauth, Ueberauth.Strategy.Steam, api_key: "testkey")

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :steam_app_id,
      "12345"
    )

    # Ensure a test steam api key is available for steam lookups
    Application.put_env(:ueberauth, Ueberauth.Strategy.Steam, api_key: "testkey")

    on_exit(fn ->
      Application.delete_env(:game_server_core, :apple_test_jwk)
      Application.delete_env(:game_server_core, :oauth_exchanger_client)
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Steam)

      GameServer.SettingsHelpers.delete(
        :game_server_core,
        GameServer.OAuth.Providers,
        :steam_app_id
      )
    end)

    :ok
  end

  describe "exchange_discord_code/4" do
    test "returns user info on success" do
      assert {:ok, %{"email" => "d@example.com"}} =
               Exchanger.exchange_discord_code("ok_code", "cid", "sec", "r")
    end

    test "returns error on failure" do
      assert {:error, _} = Exchanger.exchange_discord_code("bad_code", "cid", "sec", "r")
    end
  end

  describe "exchange_google_code/4" do
    test "returns user info on success" do
      assert {:ok, %{"email" => "g@example.com"}} =
               Exchanger.exchange_google_code("ok_code", "cid", "sec", "r")
    end

    test "returns error on token exchange failure" do
      # the TestClient returns status 400 so the function should return error
      assert {:error, _} = Exchanger.exchange_google_code("bad", "cid", "sec", "r")
    end
  end

  describe "exchange_facebook_code/4" do
    test "returns user info on success" do
      assert {:ok, %{"email" => "f@example.com"}} =
               Exchanger.exchange_facebook_code("ok_code", "cid", "sec", "r")
    end

    test "returns error if user info parse fails" do
      # Provide a flow where exchange returns non-200
      assert {:error, _} = Exchanger.exchange_facebook_code("bad", "cid", "sec", "r")
    end
  end

  describe "exchange_apple_code/4" do
    test "parses id_token and returns user info on success" do
      assert {:ok, %{"email" => "a@example.com"}} =
               Exchanger.exchange_apple_code("ok_code", "cid", "secret", "r")
    end

    test "returns error when exchange fails" do
      assert {:error, _} = Exchanger.exchange_apple_code("bad", "cid", "secret", "r")
    end
  end

  describe "exchange_steam_code/1" do
    test "returns player info when steam id found" do
      assert {:ok, %{"id" => "12345", "display_name" => "steam_user"}} =
               Exchanger.exchange_steam_code("steam:12345")
    end

    test "returns error when no player found" do
      assert {:error, _} = Exchanger.exchange_steam_code("steam:notfound")
    end
  end

  describe "exchange_steam_ticket/1" do
    test "valid ticket returns owner steam id and profile" do
      assert {:ok,
              %{
                "id" => "99999",
                "display_name" => "steam_ticket_user",
                "profile_url" => "https://steam/profile/99999"
              }} =
               Exchanger.exchange_steam_ticket("valid_ticket")
    end

    test "valid ticket can return only id when fetch_profile=false" do
      assert {:ok, %{"id" => "99999"}} =
               Exchanger.exchange_steam_ticket("valid_ticket", fetch_profile: false)
    end

    test "invalid ticket returns error" do
      assert {:error, _} = Exchanger.exchange_steam_ticket("invalid_ticket")
    end
  end
end
