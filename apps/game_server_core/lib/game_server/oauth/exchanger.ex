defmodule GameServer.OAuth.Exchanger do
  @moduledoc """
  Default implementation for exchanging OAuth codes with providers.

  This module is intentionally small and works with the Req library.
  Tests may replace the exchanger via application config for easier stubbing.
  """

  @apple_jwks_url "https://appleid.apple.com/auth/keys"
  @apple_issuer "https://appleid.apple.com"
  @apple_allowed_algs ["RS256"]
  @jwt_clock_skew_seconds 60

  @spec exchange_discord_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def exchange_discord_code(code, client_id, client_secret, redirect_uri, _opts \\ []) do
    url = "https://discord.com/api/oauth2/token"

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case http_client().post(url, form: body, headers: headers) do
      {:ok, %{status: 200, body: %{"access_token" => access_token}}} ->
        # Get user info with access token
        user_url = "https://discord.com/api/users/@me"
        auth_headers = [{"Authorization", "Bearer #{access_token}"}]

        case http_client().get(user_url, headers: auth_headers) do
          {:ok, %{status: 200, body: user_info}} ->
            {:ok, user_info}

          _ ->
            {:error, "Failed to get user info"}
        end

      _ ->
        {:error, "Failed to exchange code"}
    end
  end

  @spec exchange_google_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def exchange_google_code(code, client_id, client_secret, redirect_uri, opts \\ []) do
    url = "https://oauth2.googleapis.com/token"

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case http_client().post(url, form: body, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        if Keyword.get(opts, :fetch_profile, true) == false do
          google_handle_minimal(body, code, client_id, client_secret, redirect_uri)
        else
          google_handle_full(body)
        end

      _ ->
        {:error, "Failed to exchange code"}
    end
  end

  defp google_handle_minimal(body, code, client_id, client_secret, redirect_uri) do
    case Map.get(body, "id_token") do
      id_token when is_binary(id_token) ->
        case parse_id_token(id_token) do
          {:ok, parsed} when is_map(parsed) ->
            id = parsed["sub"] || parsed["id"]
            {:ok, Map.put(parsed, "id", id)}

          _ ->
            # cannot parse id_token -> fall back to full profile flow
            exchange_google_code(code, client_id, client_secret, redirect_uri,
              fetch_profile: true
            )
        end

      _ ->
        # no id_token -> perform full flow
        exchange_google_code(code, client_id, client_secret, redirect_uri, fetch_profile: true)
    end
  end

  defp google_handle_full(body) do
    case Map.get(body, "access_token") do
      access_token when is_binary(access_token) ->
        user_url = "https://www.googleapis.com/oauth2/v2/userinfo"
        auth_headers = [{"Authorization", "Bearer #{access_token}"}]

        case http_client().get(user_url, headers: auth_headers) do
          {:ok, %{status: 200, body: user_info}} -> {:ok, user_info}
          _ -> {:error, "Failed to get user info"}
        end

      _ ->
        {:error, "Failed to exchange code"}
    end
  end

  @spec exchange_facebook_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def exchange_facebook_code(code, client_id, client_secret, redirect_uri, _opts \\ []) do
    url = "https://graph.facebook.com/v18.0/oauth/access_token"

    params = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      redirect_uri: redirect_uri
    }

    case http_client().get(url, params: params) do
      {:ok, %{status: 200, body: %{"access_token" => access_token}}} ->
        # Get user info with access token
        user_url = "https://graph.facebook.com/v18.0/me"

        user_params = %{
          # request picture and name from facebook so we can map display_name and avatar url
          fields: "id,email,name,picture",
          access_token: access_token
        }

        case http_client().get(user_url, params: user_params) do
          {:ok, %{status: 200, body: user_info}} when is_map(user_info) ->
            {:ok, user_info}

          {:ok, %{status: 200, body: user_info}} when is_binary(user_info) ->
            # Parse JSON string if needed
            case Jason.decode(user_info) do
              {:ok, parsed} -> {:ok, parsed}
              _ -> {:error, "Failed to parse user info"}
            end

          _ ->
            {:error, "Failed to get user info"}
        end

      _ ->
        {:error, "Failed to exchange code"}
    end
  end

  @spec exchange_apple_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def exchange_apple_code(code, client_id, client_secret, _redirect_uri, opts \\ []) do
    require Logger
    url = "https://appleid.apple.com/auth/token"

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "authorization_code",
      code: code
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    Logger.info("Apple OAuth: Exchanging code with Apple. URL: #{url}")

    case http_client().post(url, form: body, headers: headers) do
      {:ok, %{status: 200, body: %{"id_token" => id_token} = _body}} ->
        Logger.info("Apple OAuth: Successfully received id_token")
        # Validate the JWT id_token and extract user info
        case parse_apple_id_token(id_token, audience: client_id) do
          {:ok, user_info} ->
            # If caller requested minimal data, just return subject/email (avoid extra work)
            if Keyword.get(opts, :fetch_profile, true) == false do
              {:ok, Map.take(user_info, ["sub", "email"])}
            else
              Logger.info("Apple OAuth: Successfully validated id_token")
              {:ok, user_info}
            end

          {:error, reason} ->
            Logger.error("Apple OAuth: Failed to parse id_token: #{inspect(reason)}")
            {:error, "Failed to parse id_token"}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Apple OAuth: Token exchange failed with status #{status}. Body: #{inspect(body)}"
        )

        {:error, "Failed to exchange code: #{status}"}

      {:error, error} ->
        Logger.error("Apple OAuth: Request failed: #{inspect(error)}")
        {:error, "Failed to exchange code"}
    end
  end

  # Validate Apple's JWT id_token and extract user information.
  @doc false
  def parse_apple_id_token(id_token, opts \\ []) do
    with {:ok, header} <- parse_jwt_part(id_token, 0),
         :ok <- validate_apple_header(header),
         {:ok, jwk} <- apple_jwk(header["kid"]),
         {:ok, claims} <- verify_apple_jwt(id_token, jwk),
         :ok <- validate_apple_claims(claims, opts) do
      {:ok, claims}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # Generic id_token parser usable for OpenID id_tokens across providers
  defp parse_id_token(id_token) do
    parse_jwt_part(id_token, 1)
  end

  defp parse_jwt_part(id_token, index) do
    case String.split(id_token, ".") do
      parts when length(parts) == 3 ->
        part = Enum.at(parts, index)
        padded = part <> String.duplicate("=", rem(4 - rem(String.length(part), 4), 4))

        with {:ok, decoded} <- Base.url_decode64(padded),
             {:ok, parsed} <- Jason.decode(decoded) do
          {:ok, parsed}
        else
          _ -> {:error, "Invalid JWT token"}
        end

      _ ->
        {:error, "Invalid JWT token"}
    end
  end

  defp validate_apple_header(%{"alg" => "RS256", "kid" => kid}) when is_binary(kid), do: :ok
  defp validate_apple_header(_header), do: {:error, :invalid_header}

  defp apple_jwk(kid) do
    with {:ok, keys} <- fetch_apple_jwks(),
         %{} = jwk_map <- Enum.find(keys, &(Map.get(&1, "kid") == kid)) do
      {:ok, JOSE.JWK.from_map(jwk_map)}
    else
      nil -> {:error, :unknown_key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_apple_jwks do
    case http_client().get(@apple_jwks_url) do
      {:ok, %{status: 200, body: body}} ->
        normalize_apple_jwks_body(body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:apple_jwks_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_apple_jwks_body(%{"keys" => keys}) when is_list(keys), do: {:ok, keys}

  defp normalize_apple_jwks_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"keys" => keys}} when is_list(keys) -> {:ok, keys}
      _ -> {:error, :invalid_apple_jwks}
    end
  end

  defp normalize_apple_jwks_body(_body), do: {:error, :invalid_apple_jwks}

  defp verify_apple_jwt(id_token, jwk) do
    case JOSE.JWT.verify_strict(jwk, @apple_allowed_algs, id_token) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp validate_apple_claims(claims, opts) when is_map(claims) do
    with :ok <- validate_apple_subject(claims["sub"]),
         :ok <- validate_apple_issuer(claims["iss"]),
         :ok <- validate_apple_audience(claims["aud"], apple_audiences(opts)),
         :ok <- validate_apple_expiration(claims["exp"]) do
      validate_apple_nonce(claims["nonce"], Keyword.get(opts, :nonce))
    end
  end

  defp validate_apple_claims(_claims, _opts), do: {:error, :invalid_claims}

  defp validate_apple_subject(sub) when is_binary(sub) and byte_size(sub) > 0, do: :ok
  defp validate_apple_subject(_sub), do: {:error, :missing_subject}

  defp validate_apple_issuer(@apple_issuer), do: :ok
  defp validate_apple_issuer(_iss), do: {:error, :invalid_issuer}

  defp validate_apple_audience(_aud, []), do: {:error, :missing_audience}

  defp validate_apple_audience(aud, audiences) when is_binary(aud) do
    if aud in audiences, do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_apple_audience(aud, audiences) when is_list(aud) do
    if Enum.any?(aud, &(&1 in audiences)), do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_apple_audience(_aud, _audiences), do: {:error, :invalid_audience}

  defp apple_audiences(opts) do
    opts
    |> Keyword.get(:audience, [
      GameServer.Settings.get(GameServer.OAuth.Providers, :apple_client_id),
      GameServer.Settings.get(GameServer.OAuth.Providers, :apple_ios_client_id)
    ])
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp validate_apple_expiration(exp) when is_integer(exp) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    if exp > now - @jwt_clock_skew_seconds do
      :ok
    else
      {:error, :expired}
    end
  end

  defp validate_apple_expiration(exp) when is_binary(exp) do
    case Integer.parse(exp) do
      {int, ""} -> validate_apple_expiration(int)
      _ -> {:error, :invalid_expiration}
    end
  end

  defp validate_apple_expiration(_exp), do: {:error, :invalid_expiration}

  defp validate_apple_nonce(_nonce, nil), do: :ok

  defp validate_apple_nonce(nonce, expected_nonce) when is_binary(expected_nonce) do
    if nonce == expected_nonce, do: :ok, else: {:error, :invalid_nonce}
  end

  # Helper to allow injecting a test HTTP client in tests. Defaults to Req.
  defp http_client do
    Application.get_env(:game_server_core, :oauth_exchanger_client, Req)
  end

  @spec exchange_steam_code(String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_steam_code(code) do
    api_key =
      Application.get_env(:ueberauth, Ueberauth.Strategy.Steam)[:api_key] ||
        GameServer.Settings.get(GameServer.OAuth.Providers, :steam_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      # Accept either a steam id or a prefixed value like "steam:12345"
      steam_id =
        case String.split(code, ":") do
          ["steam", id] -> id
          [id] -> id
          _ -> code
        end

      url = "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/"

      params = %{key: api_key, steamids: steam_id}

      case http_client().get(url, params: params) do
        {:ok, %{status: 200, body: %{"response" => %{"players" => [player | _]}}}} ->
          # Normalize returned player info to a minimal map usable by caller
          {:ok,
           %{
             "id" => to_string(steam_id),
             "display_name" => player["personaname"],
             "profile_url" => player["profileurl"],
             "avatar" => player["avatarfull"] || player["avatar"]
           }}

        _ ->
          {:error, :invalid_steam_response}
      end
    end
  end

  @doc """
  Verify a Steam auth ticket using ISteamUserAuth/AuthenticateUserTicket/v1

  Expects a ticket (binary blob) returned by the Steamworks client SDK. Returns
  {:ok, user_info} on successful verification or {:error, reason} on failure.
  """
  @spec exchange_steam_ticket(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def exchange_steam_ticket(ticket, opts \\ []) when is_binary(ticket) and is_list(opts) do
    api_key =
      Application.get_env(:ueberauth, Ueberauth.Strategy.Steam)[:api_key] ||
        GameServer.Settings.get(GameServer.OAuth.Providers, :steam_api_key)

    appid = GameServer.Settings.get(GameServer.OAuth.Providers, :steam_app_id)

    if is_nil(api_key) or api_key == "" or is_nil(appid) or appid == "" do
      {:error, :missing_config}
    else
      url = "https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/"
      params = %{key: api_key, appid: appid, ticket: ticket}

      with {:ok,
            %{status: 200, body: %{"response" => %{"params" => params_map, "result" => result}}}} <-
             http_client().post(url, form: params),
           true <- result in ["OK", "ok"],
           steamid when is_binary(steamid) <-
             params_map["ownersteamid"] || params_map["steamid"] do
        if Keyword.get(opts, :fetch_profile, true) do
          steam_profile_for(api_key, steamid)
        else
          {:ok, %{"id" => to_string(steamid)}}
        end
      else
        nil ->
          {:error, :no_steamid}

        {:ok, %{status: 200, body: %{"response" => %{"result" => result}}}} ->
          {:error, {:steam_result, result}}

        _ ->
          {:error, :invalid_steam_response}
      end
    end
  end

  # Fetch a public profile for a steamid using GetPlayerSummaries.
  # Returns {:ok, %{"id" => id, ...}} even if no player info is available.
  defp steam_profile_for(api_key, steamid) do
    url = "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/"
    params = %{key: api_key, steamids: steamid}

    case http_client().get(url, params: params) do
      {:ok, %{status: 200, body: %{"response" => %{"players" => [player | _]}}}} ->
        {:ok,
         %{
           "id" => to_string(steamid),
           "display_name" => player["personaname"],
           "profile_url" => player["profileurl"],
           "avatar" => player["avatarfull"] || player["avatar"]
         }}

      _ ->
        {:ok, %{"id" => to_string(steamid)}}
    end
  end

  @doc """
  Fetch a public Steam profile for a given steamid using GetPlayerSummaries.
  Returns {:ok, map} or {:error, reason}.
  """
  def get_player_profile(steamid) when is_binary(steamid) do
    api_key =
      Application.get_env(:ueberauth, Ueberauth.Strategy.Steam)[:api_key] ||
        GameServer.Settings.get(GameServer.OAuth.Providers, :steam_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      steam_profile_for(api_key, steamid)
    end
  end
end
