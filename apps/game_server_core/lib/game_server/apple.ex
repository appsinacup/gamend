defmodule GameServer.Apple do
  @moduledoc """
  Apple OAuth client secret generation for Ueberauth.

  Apple requires client secrets to be generated dynamically as they expire after 6 months.
  This module handles the generation and caching of Apple client secrets.
  """

  # 6 months
  # 86_400 (seconds in a day) * 180 (approx. 6 months)
  @expiration_sec 86_400 * 180

  @doc """
  Generates or retrieves a cached Apple client secret.

  Returns the client secret string, either from cache or newly generated.
  """
  @spec client_secret(keyword) :: String.t()
  def client_secret(opts \\ []) do
    client_id = resolve_client_id!(opts)

    case get_client_secret_from_cache(client_id) do
      {:ok, secret} ->
        secret

      {:error, :not_found} ->
        # Get the private key and convert escaped newlines to actual newlines
        private_key_raw = GameServer.Settings.get(GameServer.OAuth.Providers, :apple_private_key)

        if is_nil(private_key_raw) do
          raise "APPLE_PRIVATE_KEY environment variable is not set"
        end

        # Handle different formats:
        # 1. Replace escaped newlines with actual newlines (\n -> newline)
        # 2. If key is in single-line format with spaces, reconstruct with newlines
        private_key =
          private_key_raw
          |> String.replace("\\n", "\n")
          |> format_pem_key()

        secret_attrs = %{
          client_id: client_id,
          expires_in: @expiration_sec,
          key_id: GameServer.Settings.get(GameServer.OAuth.Providers, :apple_key_id),
          team_id: GameServer.Settings.get(GameServer.OAuth.Providers, :apple_team_id),
          private_key: private_key
        }

        secret = UeberauthApple.generate_client_secret(secret_attrs)

        put_client_secret_in_cache(client_id, secret, @expiration_sec)
        secret
    end
  end

  defp resolve_client_id!(opts) do
    cond do
      is_binary(Keyword.get(opts, :client_id)) ->
        Keyword.get(opts, :client_id)

      Keyword.get(opts, :client) == :web ->
        GameServer.Settings.get(GameServer.OAuth.Providers, :apple_client_id) ||
          raise "APPLE_WEB_CLIENT_ID environment variable is not set"

      Keyword.get(opts, :client) == :ios ->
        GameServer.Settings.get(GameServer.OAuth.Providers, :apple_ios_client_id) ||
          raise "APPLE_IOS_CLIENT_ID environment variable is not set"

      true ->
        GameServer.Settings.get(GameServer.OAuth.Providers, :apple_client_id) ||
          GameServer.Settings.get(GameServer.OAuth.Providers, :apple_ios_client_id) ||
          raise "APPLE_WEB_CLIENT_ID / APPLE_IOS_CLIENT_ID environment variable is not set"
    end
  end

  # Format PEM key properly with newlines
  defp format_pem_key(key) do
    # If the key already has newlines, return as-is
    if String.contains?(key, "\n") do
      key
    else
      # Single-line format: split into proper PEM format
      # PEM keys should have the header, 64-char lines, and footer
      key
      |> String.replace("-----BEGIN PRIVATE KEY----- ", "-----BEGIN PRIVATE KEY-----\n")
      |> String.replace(" -----END PRIVATE KEY-----", "\n-----END PRIVATE KEY-----")
      |> then(fn formatted ->
        # Split the middle content into 64-character lines
        [header | rest] = String.split(formatted, "\n")
        [footer | body_reversed] = Enum.reverse(rest)
        body = Enum.reverse(body_reversed) |> Enum.join()

        # Split body into 64-char chunks
        body_lines =
          body
          |> String.graphemes()
          |> Enum.chunk_every(64)
          |> Enum.map(&Enum.join/1)

        [header, body_lines, footer]
        |> List.flatten()
        |> Enum.join("\n")
      end)
    end
  end

  # Simple cache implementation using ETS
  defp get_client_secret_from_cache(client_id) do
    cache_key = {:client_secret, client_id}

    case :ets.lookup(:apple_oauth_cache, cache_key) do
      [{^cache_key, secret, expires_at}] ->
        if expires_at > System.system_time(:second) do
          {:ok, secret}
        else
          {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp put_client_secret_in_cache(client_id, secret, ttl_seconds) do
    # Ensure ETS table exists
    case :ets.info(:apple_oauth_cache) do
      :undefined ->
        :ets.new(:apple_oauth_cache, [:named_table, :public, :set])

      _ ->
        :ok
    end

    expires_at = System.system_time(:second) + ttl_seconds

    cache_key = {:client_secret, client_id}
    :ets.insert(:apple_oauth_cache, {cache_key, secret, expires_at})
  end
end
