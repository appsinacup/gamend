defmodule GameServerWeb.UserChannelKvTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias GameServer.Accounts
  alias GameServer.AccountsFixtures
  alias GameServer.Hooks.PluginManager
  alias GameServer.KV
  alias GameServer.Lobbies
  alias GameServerWeb.Auth.Guardian

  @endpoint GameServerWeb.Endpoint

  setup tags do
    GameServer.DataCase.setup_sandbox(tags)

    original_hooks_module = Application.get_env(:game_server_core, :hooks_module)

    original_plugins_dir =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :plugins_dir)

    plugin_root =
      Path.join(System.tmp_dir!(), "gs-empty-plugins-#{System.unique_integer([:positive])}")

    File.mkdir_p!(plugin_root)
    Application.put_env(:game_server_core, :hooks_module, GameServer.Hooks.Default)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :plugins_dir,
      plugin_root
    )

    _ = PluginManager.reload()

    on_exit(fn ->
      if original_hooks_module do
        Application.put_env(:game_server_core, :hooks_module, original_hooks_module)
      else
        Application.delete_env(:game_server_core, :hooks_module)
      end

      if original_plugins_dir do
        GameServer.SettingsHelpers.put(
          :game_server_core,
          GameServer.ContentSettings,
          :plugins_dir,
          original_plugins_dir
        )
      else
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.ContentSettings,
          :plugins_dir
        )
      end

      _ = PluginManager.reload()
      File.rm_rf(plugin_root)
    end)

    :ok
  end

  test "kv:subscribe rejects missing key" do
    socket = join_user_channel(user_fixture())

    ref = push(socket, "kv:subscribe", %{})

    assert_reply ref, :error, %{error: "invalid_key"}
  end

  test "kv:subscribe owner_only allows requested user owner" do
    install_kv_access(:owner_only)

    owner = user_fixture()
    other = user_fixture()
    key = unique_key("ws_user_key")
    {:ok, _entry} = KV.put(key, %{"v" => 2}, %{}, user_id: owner.id)

    owner_socket = join_user_channel(owner)
    other_socket = join_user_channel(other)

    owner_ref = push(owner_socket, "kv:subscribe", %{"key" => key, "user_id" => owner.id})
    assert_reply owner_ref, :ok, %{subscribed: true, data: %{"v" => 2}, metadata: %{}}

    other_ref = push(other_socket, "kv:subscribe", %{"key" => key, "user_id" => owner.id})
    assert_reply other_ref, :error, %{error: "forbidden"}
  end

  test "kv:subscribe lobby_members_only allows requested lobby members" do
    install_kv_access(:lobby_members_only)

    host = user_fixture()
    member = user_fixture()
    outsider = user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "ws-kv-room", host_id: host.id})
    {:ok, _member} = Lobbies.join_lobby(member, lobby)
    key = unique_key("ws_lobby_key")
    {:ok, _entry} = KV.put(key, %{"v" => 3}, %{}, lobby_id: lobby.id)

    member_socket = join_user_channel(member)
    outsider_socket = join_user_channel(outsider)

    member_ref = push(member_socket, "kv:subscribe", %{"key" => key, "lobby_id" => lobby.id})
    assert_reply member_ref, :ok, %{subscribed: true, data: %{"v" => 3}, metadata: %{}}

    outsider_ref =
      push(outsider_socket, "kv:subscribe", %{"key" => key, "lobby_id" => lobby.id})

    assert_reply outsider_ref, :error, %{error: "forbidden"}
  end

  test "kv:subscribe owner_or_lobby_member allows owner or requested lobby member" do
    install_kv_access(:owner_or_lobby_member)

    owner = user_fixture()
    host = user_fixture()
    member = user_fixture()
    outsider = user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "ws-kv-shared-room", host_id: host.id})
    {:ok, _member} = Lobbies.join_lobby(member, lobby)

    key = unique_key("ws_shared_key")
    {:ok, _entry} = KV.put(key, %{"scope" => "user"}, %{}, user_id: owner.id)
    {:ok, _entry} = KV.put(key, %{"scope" => "lobby"}, %{}, lobby_id: lobby.id)

    owner_socket = join_user_channel(owner)
    member_socket = join_user_channel(member)
    outsider_socket = join_user_channel(outsider)

    owner_ref = push(owner_socket, "kv:subscribe", %{"key" => key, "user_id" => owner.id})
    assert_reply owner_ref, :ok, %{subscribed: true, data: %{"scope" => "user"}, metadata: %{}}

    member_ref =
      push(member_socket, "kv:subscribe", %{"key" => key, "lobby_id" => lobby.id})

    assert_reply member_ref, :ok, %{subscribed: true, data: %{"scope" => "lobby"}, metadata: %{}}

    user_ref =
      push(outsider_socket, "kv:subscribe", %{"key" => key, "user_id" => owner.id})

    assert_reply user_ref, :error, %{error: "forbidden"}

    lobby_ref =
      push(outsider_socket, "kv:subscribe", %{"key" => key, "lobby_id" => lobby.id})

    assert_reply lobby_ref, :error, %{error: "forbidden"}
  end

  test "kv:subscribe admin_only allows only admins" do
    install_kv_access(:admin_only)

    user = non_admin_fixture()
    admin = admin_fixture()
    key = unique_key("ws_admin_key")
    {:ok, _entry} = KV.put(key, %{"v" => 4}, %{})

    user_socket = join_user_channel(user)
    admin_socket = join_user_channel(admin)

    user_ref = push(user_socket, "kv:subscribe", %{"key" => key})
    assert_reply user_ref, :error, %{error: "forbidden"}

    admin_ref = push(admin_socket, "kv:subscribe", %{"key" => key})
    assert_reply admin_ref, :ok, %{subscribed: true, data: %{"v" => 4}, metadata: %{}}
  end

  test "kv:subscribe server_only blocks clients" do
    install_kv_access(:server_only)

    user = user_fixture()
    admin = admin_fixture()
    key = unique_key("ws_server_key")
    {:ok, _entry} = KV.put(key, %{"v" => 5}, %{})

    user_socket = join_user_channel(user)
    admin_socket = join_user_channel(admin)

    user_ref = push(user_socket, "kv:subscribe", %{"key" => key})
    assert_reply user_ref, :error, %{error: "forbidden"}

    admin_ref = push(admin_socket, "kv:subscribe", %{"key" => key})
    assert_reply admin_ref, :error, %{error: "forbidden"}
  end

  test "kv:subscribe returns current value and streams updates" do
    user = user_fixture()
    key = unique_key("ws_stream_key")
    {:ok, _entry} = KV.put(key, %{"v" => 1}, %{"version" => "one"})
    socket = join_user_channel(user)

    ref = push(socket, "kv:subscribe", %{"key" => key, "_request_id" => "sub-1"})

    assert_reply ref, :ok, %{
      subscribed: true,
      key: ^key,
      user_id: nil,
      lobby_id: nil,
      data: %{"v" => 1},
      metadata: %{"version" => "one"},
      _request_id: "sub-1"
    }

    {:ok, _entry} = KV.put(key, %{"v" => 2}, %{"version" => "two"})

    assert_push "kv_updated", %{
      key: ^key,
      user_id: nil,
      lobby_id: nil,
      data: %{"v" => 2},
      metadata: %{"version" => "two"}
    }
  end

  test "kv:subscribe returns missing state and streams first later update" do
    key = unique_key("ws_missing_stream_key")
    socket = join_user_channel(user_fixture())

    ref = push(socket, "kv:subscribe", %{"key" => key})

    assert_reply ref, :ok, %{
      subscribed: true,
      key: ^key,
      user_id: nil,
      lobby_id: nil,
      missing: true
    }

    {:ok, _entry} = KV.put(key, %{"created" => true}, %{})

    assert_push "kv_updated", %{
      key: ^key,
      data: %{"created" => true},
      metadata: %{}
    }
  end

  test "kv:subscribe streams deletes" do
    key = unique_key("ws_delete_stream_key")
    {:ok, _entry} = KV.put(key, %{"v" => 1}, %{})
    socket = join_user_channel(user_fixture())

    ref = push(socket, "kv:subscribe", %{"key" => key})
    assert_reply ref, :ok, %{subscribed: true}

    :ok = KV.delete(key)

    assert_push "kv_deleted", %{key: ^key, user_id: nil, lobby_id: nil}
  end

  test "kv:unsubscribe stops update stream" do
    key = unique_key("ws_unsubscribe_stream_key")
    socket = join_user_channel(user_fixture())

    subscribe_ref = push(socket, "kv:subscribe", %{"key" => key})
    assert_reply subscribe_ref, :ok, %{subscribed: true}

    unsubscribe_ref = push(socket, "kv:unsubscribe", %{"key" => key, "_request_id" => "unsub-1"})

    assert_reply unsubscribe_ref, :ok, %{
      unsubscribed: true,
      key: ^key,
      user_id: nil,
      lobby_id: nil,
      _request_id: "unsub-1"
    }

    {:ok, _entry} = KV.put(key, %{"v" => "after-unsubscribe"}, %{})

    refute_push "kv_updated", %{key: ^key}, 100
  end

  test "kv:subscribe enforces read access" do
    install_kv_access(:owner_only)

    owner = user_fixture()
    other = user_fixture()
    key = unique_key("ws_owner_stream_key")
    {:ok, _entry} = KV.put(key, %{"v" => 1}, %{}, user_id: owner.id)
    socket = join_user_channel(other)

    ref = push(socket, "kv:subscribe", %{"key" => key, "user_id" => owner.id})

    assert_reply ref, :error, %{error: "forbidden"}
  end

  defp join_user_channel(user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GameServerWeb.UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    assert_push "updated", _user_payload

    socket
  end

  defp install_kv_access(access) do
    mod_name = String.to_atom("TestChannelKvAccess_#{System.unique_integer([:positive])}")
    access = Macro.escape(access)

    Module.create(
      mod_name,
      quote do
        def before_kv_get(_key, _opts), do: unquote(access)
      end,
      Macro.Env.location(__ENV__)
    )

    Application.put_env(:game_server_core, :hooks_module, mod_name)
  end

  defp user_fixture, do: AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

  defp unique_key(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"

  defp non_admin_fixture do
    user = user_fixture()
    {:ok, user} = Accounts.update_user(user, %{is_admin: false})
    user
  end

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})
    admin
  end
end
