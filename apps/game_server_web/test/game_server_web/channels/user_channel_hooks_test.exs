defmodule GameServerWeb.UserChannelHooksTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias GameServer.AccountsFixtures
  alias GameServer.Hooks.PluginManager
  alias GameServerWeb.Auth.Guardian

  @endpoint GameServerWeb.Endpoint

  setup tags do
    GameServer.DataCase.setup_sandbox(tags)

    # Set up a temporary plugin
    tmp = Path.join(System.tmp_dir!(), "gs-plugin-ch-#{System.unique_integer([:positive])}")
    plugin_root = Path.join(tmp, "modules/plugins")
    plugin_name = "channel_test_plugin"
    plugin_dir = Path.join(plugin_root, plugin_name)
    ebin_dir = Path.join(plugin_dir, "ebin")

    File.mkdir_p!(ebin_dir)

    hook_mod = Module.concat([GameServer, ChannelTestPluginHook])

    {:module, ^hook_mod, beam, _} =
      Module.create(
        hook_mod,
        quote do
          @behaviour GameServer.Hooks

          def after_startup, do: :ok
          def before_stop, do: :ok
          def after_user_register(_user), do: :ok
          def after_user_logged_in(_user), do: :ok
          def after_user_updated(_user), do: :ok
          def before_user_update(_user, attrs), do: {:ok, attrs}

          def before_lobby_create(attrs), do: {:ok, attrs}
          def after_lobby_create(_lobby), do: :ok
          def before_group_create(_user, attrs), do: {:ok, attrs}
          def after_group_create(_group), do: :ok
          def before_group_join(user, group, opts), do: {:ok, {user, group, opts}}
          def before_group_update(_group, attrs), do: {:ok, attrs}
          def after_group_updated(_group), do: :ok
          def before_lobby_join(user, lobby, opts), do: {:ok, {user, lobby, opts}}
          def before_chat_message(_user, attrs), do: {:ok, attrs}
          def after_chat_message(_message), do: :ok
          def after_lobby_join(_user, _lobby), do: :ok
          def before_lobby_leave(user, lobby), do: {:ok, {user, lobby}}
          def after_lobby_leave(_user, _lobby), do: :ok
          def before_lobby_update(_lobby, attrs), do: {:ok, attrs}
          def after_lobby_updated(_lobby), do: :ok
          def before_lobby_delete(lobby), do: {:ok, lobby}
          def after_lobby_deleted(_lobby), do: :ok
          def before_lobby_kick(host, target, lobby), do: {:ok, {host, target, lobby}}
          def after_lobby_kick(_host, _target, _lobby), do: :ok
          def after_lobby_host_change(_lobby, _new_host_id), do: :ok
          def after_group_join(_user_id, _group), do: :ok
          def after_group_leave(_user_id, _group_id), do: :ok
          def after_group_deleted(_group), do: :ok
          def after_group_kick(_admin_id, _target_id, _group_id), do: :ok
          def before_party_create(_user, attrs), do: {:ok, attrs}
          def after_party_create(_party), do: :ok
          def before_party_update(_party, attrs), do: {:ok, attrs}
          def after_party_updated(_party), do: :ok
          def after_party_join(_user, _party), do: :ok
          def after_party_leave(_user, _party_id), do: :ok
          def after_party_kick(_target, _leader, _party), do: :ok
          def after_party_disband(_party), do: :ok

          def before_kv_get(_key, _opts), do: :public
          def on_custom_hook(_hook, _args), do: {:error, :not_implemented}

          def echo(val), do: val

          def greet do
            user = GameServer.Hooks.caller_user()
            %{user_id: user.id}
          end
        end,
        __ENV__
      )

    beam_path = Path.join(ebin_dir, Atom.to_string(hook_mod) <> ".beam")
    File.write!(beam_path, beam)

    app_term =
      {:application, String.to_atom(plugin_name),
       [
         {:description, ~c"channel test plugin"},
         {:vsn, ~c"0.1.0"},
         {:modules, [hook_mod]},
         {:registered, []},
         {:applications, [:kernel, :stdlib]},
         {:env, [hooks_module: to_charlist(Atom.to_string(hook_mod))]}
       ]}

    app_text = :io_lib.format(~c"~p.~n", [app_term]) |> IO.iodata_to_binary()
    File.write!(Path.join(ebin_dir, "#{plugin_name}.app"), app_text)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :plugins_dir,
      plugin_root
    )

    _ = PluginManager.reload()

    user = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GameServerWeb.UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    # Drain the initial "updated" push
    assert_push "updated", _user_payload

    on_exit(fn ->
      GameServer.SettingsHelpers.delete(
        :game_server_core,
        GameServer.ContentSettings,
        :plugins_dir
      )

      _ = PluginManager.reload()
    end)

    {:ok, socket: socket, user: user, plugin: plugin_name}
  end

  test "call_hook returns result from plugin function", %{socket: socket, plugin: plugin} do
    ref = push(socket, "call_hook", %{"plugin" => plugin, "fn" => "echo", "args" => ["hello"]})
    assert_reply ref, :ok, %{data: "hello"}
  end

  test "call_hook injects caller context", %{socket: socket, user: user, plugin: plugin} do
    ref = push(socket, "call_hook", %{"plugin" => plugin, "fn" => "greet", "args" => []})
    assert_reply ref, :ok, %{data: %{user_id: user_id}}
    assert user_id == user.id
  end

  test "call_hook rejects reserved hook names", %{socket: socket, plugin: plugin} do
    ref =
      push(socket, "call_hook", %{
        "plugin" => plugin,
        "fn" => "before_lobby_create",
        "args" => [%{}]
      })

    assert_reply ref, :error, %{error: "reserved_hook_name"}
  end

  test "call_hook returns error for unknown plugin", %{socket: socket} do
    ref =
      push(socket, "call_hook", %{
        "plugin" => "nonexistent_plugin",
        "fn" => "echo",
        "args" => ["test"]
      })

    assert_reply ref, :error, %{error: _reason}
  end

  test "call_hook returns error for unknown function", %{socket: socket, plugin: plugin} do
    ref =
      push(socket, "call_hook", %{
        "plugin" => plugin,
        "fn" => "nonexistent_function",
        "args" => []
      })

    assert_reply ref, :error, %{error: _reason}
  end

  test "unknown event returns error", %{socket: socket} do
    ref = push(socket, "some_unknown_event", %{})
    assert_reply ref, :error, %{error: "unknown_event"}
  end
end
