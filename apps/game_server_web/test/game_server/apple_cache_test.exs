defmodule GameServer.AppleCacheTest do
  use ExUnit.Case, async: true

  setup do
    # Ensure a clean ETS table for each test
    case :ets.info(:apple_oauth_cache) do
      :undefined -> :ok
      _ -> :ets.delete(:apple_oauth_cache)
    end

    :ok
  end

  test "client_secret returns cached value when present and not expired" do
    secret = "cached-secret-#{System.unique_integer([:positive])}"
    client_id = "com.example.web"
    # create table and insert value that is not yet expired
    :ets.new(:apple_oauth_cache, [:named_table, :public, :set])
    expires_at = System.system_time(:second) + 10_000
    :ets.insert(:apple_oauth_cache, {{:client_secret, client_id}, secret, expires_at})

    assert secret == GameServer.Apple.client_secret(client_id: client_id)
  end

  test "client_secret raises when private key missing and cache empty" do
    # ensure no cache and no APPLE_PRIVATE_KEY env var
    case :ets.info(:apple_oauth_cache) do
      :undefined -> :ok
      _ -> :ets.delete(:apple_oauth_cache)
    end

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :apple_client_id,
      "com.example.web"
    )

    old =
      GameServer.SettingsHelpers.get(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_private_key
      )

    GameServer.SettingsHelpers.delete(
      :game_server_core,
      GameServer.OAuth.Providers,
      :apple_private_key
    )

    on_exit(fn ->
      GameServer.SettingsHelpers.delete(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_client_id
      )

      if old,
        do:
          GameServer.SettingsHelpers.put(
            :game_server_core,
            GameServer.OAuth.Providers,
            :apple_private_key,
            old
          )
    end)

    assert_raise RuntimeError, fn -> GameServer.Apple.client_secret() end
  end

  test "get_client_secret_from_cache returns error when cache is expired" do
    # Create an expired cache entry
    :ets.new(:apple_oauth_cache, [:named_table, :public, :set])
    expired_secret = "expired-secret"
    expires_at = System.system_time(:second) - 100

    :ets.insert(
      :apple_oauth_cache,
      {{:client_secret, "com.example.web"}, expired_secret, expires_at}
    )

    # Calling client_secret should attempt to regenerate (and fail without env vars)
    old =
      GameServer.SettingsHelpers.get(
        :game_server_core,
        GameServer.OAuth.Providers,
        :apple_private_key
      )

    GameServer.SettingsHelpers.delete(
      :game_server_core,
      GameServer.OAuth.Providers,
      :apple_private_key
    )

    on_exit(fn ->
      if old,
        do:
          GameServer.SettingsHelpers.put(
            :game_server_core,
            GameServer.OAuth.Providers,
            :apple_private_key,
            old
          )
    end)

    # Should raise because cache is expired and env var is missing
    assert_raise RuntimeError, fn ->
      GameServer.Apple.client_secret(client_id: "com.example.web")
    end
  end
end
