defmodule GameServer.OAuth.GoogleIDToken do
  @moduledoc """
  Verifies Google OpenID Connect `id_token`s for native/mobile sign-in flows.

  This module uses Google's `tokeninfo` endpoint to validate the token and
  extract the claims required by the server.

  It is intentionally separate from the authorization-code exchange flow used
  by the web OAuth callbacks.
  """

  @tokeninfo_url "https://oauth2.googleapis.com/tokeninfo"

  @type claims :: map()

  @spec verify(String.t(), keyword()) :: {:ok, claims()} | {:error, term()}
  def verify(id_token, opts \\ [])

  def verify(id_token, opts) when is_binary(id_token) do
    expected_auds = Keyword.get(opts, :expected_auds, default_expected_auds())

    if expected_auds == [] do
      {:error, :missing_google_client_id}
    else
      case http_client().get(@tokeninfo_url, params: %{id_token: id_token}) do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          validate_claims(body, expected_auds)

        {:ok, %{status: status, body: body}} ->
          {:error, {:tokeninfo_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def verify(_id_token, _opts), do: {:error, :invalid_id_token}

  defp validate_claims(%{"sub" => sub} = claims, expected_auds) when is_binary(sub) do
    aud = Map.get(claims, "aud")

    cond do
      not aud_matches?(aud, expected_auds) ->
        {:error, :invalid_audience}

      not issuer_matches?(Map.get(claims, "iss")) ->
        {:error, :invalid_issuer}

      expired?(claims) ->
        {:error, :expired}

      true ->
        {:ok, claims}
    end
  end

  defp validate_claims(_claims, _expected_auds), do: {:error, :missing_subject}

  defp aud_matches?(aud, expected_auds) when is_binary(aud) do
    Enum.any?(expected_auds, &(&1 == aud))
  end

  defp aud_matches?(_aud, _expected_auds), do: false

  defp issuer_matches?(nil), do: true
  defp issuer_matches?("https://accounts.google.com"), do: true
  defp issuer_matches?("accounts.google.com"), do: true
  defp issuer_matches?(_), do: false

  # tokeninfo returns either expires_in (seconds as string) or exp (unix seconds as string)
  defp expired?(%{"expires_in" => expires_in}) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {sec, _} -> sec <= 0
      _ -> false
    end
  end

  defp expired?(%{"exp" => exp}) when is_binary(exp) do
    case Integer.parse(exp) do
      {unix, _} -> DateTime.to_unix(DateTime.utc_now()) >= unix
      _ -> false
    end
  end

  defp expired?(_), do: false

  defp default_expected_auds do
    # Prefer explicitly configured web client id; fall back to the existing
    # GOOGLE_CLIENT_ID used by the authorization-code exchange flow.
    #
    # For Godot/Android plugins that return an id_token, this MUST match the
    # Web Client ID you initialize the plugin with.
    auds =
      [
        GameServer.Settings.get(GameServer.OAuth.Providers, :google_web_client_id),
        GameServer.Settings.get(GameServer.OAuth.Providers, :google_client_id)
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Enum.uniq(auds)
  end

  defp http_client do
    Application.get_env(:game_server_core, :google_tokeninfo_client, Req)
  end
end
