defmodule GameServerWeb.Api.V1.HookControllerTest do
  use GameServerWeb.ConnCase, async: false

  alias GameServer.Hooks.HookSchemas
  alias GameServer.Hooks.PluginManager
  alias GameServerWeb.Auth.Guardian

  setup do
    user = GameServer.AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)

    conn = build_conn() |> put_req_header("authorization", "Bearer " <> token)

    {:ok, conn: conn, user: user}
  end

  test "POST /api/v1/hooks/call invokes plugin function", %{conn: conn, user: user} do
    tmp = Path.join(System.tmp_dir!(), "gs-plugin-#{System.unique_integer([:positive])}")
    plugin_root = Path.join(tmp, "modules/plugins")
    plugin_name = "test_plugin"
    plugin_dir = Path.join(plugin_root, plugin_name)
    ebin_dir = Path.join(plugin_dir, "ebin")

    File.mkdir_p!(ebin_dir)

    hook_mod = Module.concat([GameServer, TestPluginHook])

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

          def greet do
            user = GameServer.Hooks.caller_user()
            %{greeted: user.id}
          end

          def echo(a), do: a
          def boom, do: raise("boom")
        end,
        __ENV__
      )

    beam_path = Path.join(ebin_dir, Atom.to_string(hook_mod) <> ".beam")
    File.write!(beam_path, beam)

    app_term =
      {:application, String.to_atom(plugin_name),
       [
         {:description, ~c"test plugin"},
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

    on_exit(fn ->
      GameServer.SettingsHelpers.delete(
        :game_server_core,
        GameServer.ContentSettings,
        :plugins_dir
      )

      _ = PluginManager.reload()
    end)

    _ = PluginManager.reload()

    body = %{"plugin" => plugin_name, "fn" => "echo", "args" => [[1, 2, 3]]}
    conn = post(conn, "/api/v1/hooks/call", body)
    assert %{"data" => [1, 2, 3]} = json_response(conn, 200)

    old_request_threshold =
      Application.get_env(:game_server_web, :slow_request_threshold_ms, :unset)

    old_hook_threshold = Application.get_env(:game_server_core, :slow_hook_threshold_ms, :unset)

    Application.put_env(:game_server_web, :slow_request_threshold_ms, -1.0)
    Application.put_env(:game_server_core, :slow_hook_threshold_ms, -1.0)

    try do
      body2 = %{"plugin" => plugin_name, "fn" => "greet", "args" => []}
      id = user.id

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn2 = post(conn, "/api/v1/hooks/call?debug=1&token=secret-value", body2)
          assert %{"data" => %{"greeted" => ^id}} = json_response(conn2, 200)
        end)

      assert log =~ ~s(Slow Hook: plugin="test_plugin" fn="greet")
      assert log =~ ~s(Slow Request: POST /api/v1/hooks/call)
      assert log =~ ~s(query=)
      assert log =~ ~s("debug" => "1")
      assert log =~ ~s("token" => "[FILTERED]")
      assert log =~ ~s(body=)
      assert log =~ ~s("plugin" => "test_plugin")
      assert log =~ ~s("fn" => "greet")
      assert log =~ ~s("args" => %{"count" => 0, "types" => []})
      assert log =~ "user_id=#{inspect(id)}"
      assert log =~ "args_count=0"
      refute log =~ "secret-value"
    after
      restore_env(:slow_request_threshold_ms, old_request_threshold)
      restore_core_env(:slow_hook_threshold_ms, old_hook_threshold)
    end

    body3 = %{"plugin" => plugin_name, "fn" => "boom", "args" => []}
    conn3 = post(conn, "/api/v1/hooks/call", body3)

    assert %{"error" => "exception", "details" => details} = json_response(conn3, 400)
    assert details =~ "boom"
  end

  test "POST /api/v1/hooks/call converts typed protobuf hooks to and from JSON", %{conn: conn} do
    tmp = Path.join(System.tmp_dir!(), "gs-typed-#{System.unique_integer([:positive])}")
    plugin_root = Path.join(tmp, "modules/plugins")
    plugin_name = "typed_plugin"
    ebin_dir = Path.join([plugin_root, plugin_name, "ebin"])
    File.mkdir_p!(ebin_dir)

    # The <FnName>Request/<FnName>Reply pair is what registers the schema.
    req_mod = Module.concat([TypedPlugin, V1, GreetRequest])
    reply_mod = Module.concat([TypedPlugin, V1, GreetReply])

    {:module, ^req_mod, req_beam, _} =
      Module.create(
        req_mod,
        quote do
          use Protobuf, syntax: :proto3
          field(:name, 1, type: :string)
        end,
        __ENV__
      )

    {:module, ^reply_mod, reply_beam, _} =
      Module.create(
        reply_mod,
        quote do
          use Protobuf, syntax: :proto3
          field(:greeting, 1, type: :string)
        end,
        __ENV__
      )

    hook_mod = Module.concat([GameServer, TypedPluginHook])

    {:module, ^hook_mod, hook_beam, _} =
      Module.create(
        hook_mod,
        quote do
          # Hooks dispatch by exported function, so an RPC-only plugin needs no
          # lifecycle callbacks. Takes and returns protobuf structs, never JSON.
          def greet(%TypedPlugin.V1.GreetRequest{} = req) do
            %TypedPlugin.V1.GreetReply{greeting: "Hello, " <> req.name}
          end
        end,
        __ENV__
      )

    for {mod, beam} <- [{req_mod, req_beam}, {reply_mod, reply_beam}, {hook_mod, hook_beam}] do
      File.write!(Path.join(ebin_dir, Atom.to_string(mod) <> ".beam"), beam)
    end

    app_term =
      {:application, String.to_atom(plugin_name),
       [
         {:description, ~c"typed plugin"},
         {:vsn, ~c"0.1.0"},
         {:modules, [req_mod, reply_mod, hook_mod]},
         {:registered, []},
         {:applications, [:kernel, :stdlib]},
         {:env, [hooks_module: to_charlist(Atom.to_string(hook_mod))]}
       ]}

    File.write!(
      Path.join(ebin_dir, "#{plugin_name}.app"),
      :io_lib.format(~c"~p.~n", [app_term]) |> IO.iodata_to_binary()
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :plugins_dir,
      plugin_root
    )

    on_exit(fn ->
      GameServer.SettingsHelpers.delete(
        :game_server_core,
        GameServer.ContentSettings,
        :plugins_dir
      )

      _ = PluginManager.reload()
    end)

    _ = PluginManager.reload()

    assert %{request: ^req_mod, reply: ^reply_mod} =
             HookSchemas.lookup(plugin_name, "greet")

    # A plain JSON object in, a plain JSON map out — the hook itself only ever
    # sees the structs. Without the schema conversion this 500s on a
    # function_clause, since the hook cannot match a bare map.
    body = %{"plugin" => plugin_name, "fn" => "greet", "args" => [%{"name" => "http"}]}
    conn = post(conn, "/api/v1/hooks/call", body)
    assert %{"data" => %{"greeting" => "Hello, http"}} = json_response(conn, 200)
  end

  defp restore_env(key, :unset), do: Application.delete_env(:game_server_web, key)
  defp restore_env(key, value), do: Application.put_env(:game_server_web, key, value)
  defp restore_core_env(key, :unset), do: Application.delete_env(:game_server_core, key)
  defp restore_core_env(key, value), do: Application.put_env(:game_server_core, key, value)
end
