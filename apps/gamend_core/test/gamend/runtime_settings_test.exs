defmodule Gamend.RuntimeSettingsTest do
  @moduledoc """
  Values that used to be literals and are now declared settings: each keeps
  its old value by default and follows its setting.
  """
  # Settings are global Application config.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gamend.Accounts.StalePresenceSweeper
  alias Gamend.Hooks.PluginManager
  alias Gamend.SettingsHelpers
  alias Gamend.Storage

  defp put(module, key, value) do
    SettingsHelpers.put(:gamend_core, module, key, value)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, module, key) end)
  end

  describe "storage" do
    test "a private S3 bucket hands out a URL that does not expire" do
      put(Storage, :adapter, :s3)

      assert Storage.url("avatars/u/a.png") == "/storage/avatars/u/a.png"
    end

    test "with a public_url, S3 URLs point there, signed or not" do
      put(Storage, :adapter, :s3)
      put(Storage, :public_url, "https://cdn.example.com/")

      assert Storage.url("avatars/u/a.png") == "https://cdn.example.com/avatars/u/a.png"

      assert Storage.url("avatars/u/a.png", signed: true) ==
               "https://cdn.example.com/avatars/u/a.png"
    end

    test "an upload ticket lasts upload_ttl_seconds, on the ticket and on its token" do
      assert Storage.upload_ttl_seconds() == 600
      put(Storage, :upload_ttl_seconds, 1_800)

      assert {:ok, %{expires_in: 1_800}} = Storage.presigned_upload("avatars/u/a.png")
    end

    test "a signed link lasts at most S3's seven days" do
      assert Storage.signed_url_seconds() == 3_600
      put(Storage, :signed_url_seconds, 30 * 86_400)
      assert Storage.signed_url_seconds() == 7 * 86_400
    end
  end

  test "the cache TTL follows its setting" do
    assert Gamend.Cache.ttl() == 60_000
    put(Gamend.Cache.Settings, :ttl_ms, 5_000)
    assert Gamend.Cache.ttl() == 5_000
  end

  describe "hooks" do
    test "a hook call gets the shorter budget inside a transaction" do
      put(PluginManager, :call_timeout_ms, 30_000)
      put(PluginManager, :call_timeout_in_transaction_ms, 2_000)

      assert PluginManager.call_timeout_ms() == 30_000

      Sandbox.checkout(Gamend.Repo)

      assert {:ok, 2_000} = Gamend.Repo.transaction(fn -> PluginManager.call_timeout_ms() end)
    end
  end

  describe "presence" do
    test "the heartbeat is three fifths of the stale threshold, and at most 3 minutes" do
      assert StalePresenceSweeper.heartbeat_ms() == 180_000

      put(StalePresenceSweeper, :stale_threshold_s, 60)
      assert StalePresenceSweeper.heartbeat_ms() == 36_000

      put(StalePresenceSweeper, :stale_threshold_s, 3_600)
      assert StalePresenceSweeper.heartbeat_ms() == 180_000
    end
  end
end
