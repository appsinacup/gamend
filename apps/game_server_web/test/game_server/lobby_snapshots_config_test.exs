defmodule GameServer.LobbySnapshotsConfigTest do
  @moduledoc """
  Config resolution, kept separate from `LobbySnapshotsTest` because these cases
  need *no* app-env block — which that suite's `setup` installs for every test.

  These exist because the documented env vars used to do nothing: a host app
  evaluates its own runtime config, never core's, so `GAMEND_LOBBY_SNAPSHOTS_ENABLED=true`
  parsed fine and changed nothing while the admin page reported capture off.

  The fix is no longer a per-module env fallback but `GameServer.Settings`: the
  setting is declared once, and a host's `runtime.exs` feeds the environment
  into it with `from_env/0` — which covers every declared setting rather than
  the three that once got a hand-written fallback.
  """

  # async: false — mutates process-global app env and OS env.
  use ExUnit.Case, async: false

  alias GameServer.LobbySnapshots
  alias GameServer.Settings

  setup do
    previous_app_env = Application.get_env(:game_server_core, LobbySnapshots)
    previous_env = System.get_env("GAMEND_LOBBY_SNAPSHOTS_ENABLED")
    previous_keys = System.get_env("GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS")

    Application.delete_env(:game_server_core, LobbySnapshots)
    System.delete_env("GAMEND_LOBBY_SNAPSHOTS_ENABLED")
    System.delete_env("GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS")

    on_exit(fn ->
      restore_app_env(previous_app_env)
      restore_env("GAMEND_LOBBY_SNAPSHOTS_ENABLED", previous_env)
      restore_env("GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS", previous_keys)
    end)

    :ok
  end

  defp restore_app_env(nil), do: Application.delete_env(:game_server_core, LobbySnapshots)
  defp restore_app_env(value), do: Application.put_env(:game_server_core, LobbySnapshots, value)

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  # What a host's `config/runtime.exs` does with `from_env/0`.
  defp apply_env do
    for {app, module, opts} <- Settings.from_env(), module == LobbySnapshots do
      Application.put_env(app, module, opts)
    end
  end

  describe "enabled?/0 without a host config block" do
    test "is off when nothing is set" do
      refute LobbySnapshots.enabled?()
    end

    test "the env var alone turns capture on, once a host applies from_env/0" do
      System.put_env("GAMEND_LOBBY_SNAPSHOTS_ENABLED", "true")
      apply_env()

      assert LobbySnapshots.enabled?()
    end

    test "an explicit app-env block wins: from_env/0 never overwrites it" do
      System.put_env("GAMEND_LOBBY_SNAPSHOTS_ENABLED", "true")
      Application.put_env(:game_server_core, LobbySnapshots, enabled: false)

      refute LobbySnapshots.enabled?()
    end
  end

  describe "user_kv_keys from the environment" do
    test "splits and trims a comma list" do
      System.put_env("GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS", "cargo, progress ,ship")
      apply_env()

      assert user_kv_keys() == ["cargo", "progress", "ship"]
    end

    test "strips a trailing comment" do
      # `.env` files keep everything after `=` verbatim, so `KEY=cargo # note`
      # arrives with the comment attached. Without stripping, the filter matches
      # a key that does not exist and captures nothing — silently.
      System.put_env("GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS", "cargo   # empty = capture none")
      apply_env()

      assert user_kv_keys() == ["cargo"]
    end

    test "a comment-only value captures no keys rather than one junk key" do
      System.put_env("GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS", "  # nothing here")
      apply_env()

      assert user_kv_keys() == []
    end
  end

  describe "declaration" do
    test "the documented env names are what the settings resolve from" do
      names = Map.new(LobbySnapshots.__settings__(), &{&1.key, &1.env})

      assert names == %{
               enabled: "GAMEND_LOBBY_SNAPSHOTS_ENABLED",
               user_kv_keys: "GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS",
               max_kv_entries: "GAMEND_LOBBY_SNAPSHOTS_MAX_KV_ENTRIES"
             }
    end

    test "capture is off by default — enabling it is a deliberate privacy decision" do
      assert Settings.get(LobbySnapshots, :enabled) == false
      assert Settings.get(LobbySnapshots, :user_kv_keys) == []
    end
  end

  defp user_kv_keys, do: LobbySnapshots.resolved_config(:user_kv_keys, [])
end
