defmodule Gamend.Hooks.InternalCallPluginFanoutTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts.User
  alias Gamend.Hooks
  alias Gamend.Hooks.PluginManager

  test "internal_call runs plugin after_user_register even when base is Default" do
    tmp = Path.join(System.tmp_dir!(), "gs-hooks-fanout-#{System.unique_integer([:positive])}")
    plugin_root = Path.join(tmp, "modules/plugins")
    plugin_name = "test_plugin_fanout_#{System.unique_integer([:positive])}"
    plugin_dir = Path.join(plugin_root, plugin_name)
    ebin_dir = Path.join(plugin_dir, "ebin")

    File.mkdir_p!(ebin_dir)

    test_pid = self()

    hook_mod =
      Module.concat([
        Gamend,
        String.to_atom("TestPluginFanoutHook_#{System.unique_integer([:positive])}")
      ])

    {:module, ^hook_mod, beam, _} =
      Module.create(
        hook_mod,
        quote do
          use Gamend.Hooks

          @impl true
          def after_user_register(_user) do
            if pid = Application.get_env(:gamend, :plugin_fanout_test_pid) do
              send(pid, :after_user_register_called)
            end

            :ok
          end
        end,
        __ENV__
      )

    File.write!(Path.join(ebin_dir, Atom.to_string(hook_mod) <> ".beam"), beam)

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

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.ContentSettings,
      :plugins_dir,
      plugin_root
    )

    Application.put_env(:gamend, :plugin_fanout_test_pid, test_pid)

    original_hooks_mod = Application.get_env(:gamend_core, :hooks_module)

    on_exit(fn ->
      Gamend.SettingsHelpers.delete(
        :gamend_core,
        Gamend.ContentSettings,
        :plugins_dir
      )

      Application.delete_env(:gamend, :plugin_fanout_test_pid)

      if is_nil(original_hooks_mod) do
        Application.delete_env(:gamend_core, :hooks_module)
      else
        Application.put_env(:gamend_core, :hooks_module, original_hooks_mod)
      end

      _ = PluginManager.reload()
    end)

    _ = PluginManager.reload()

    assert {:ok, plugin} = PluginManager.lookup(plugin_name)
    assert plugin.status == :ok
    assert plugin.hooks_module == hook_mod

    Application.put_env(:gamend_core, :hooks_module, Gamend.Hooks.Default)

    assert {:ok, :ok} = Hooks.internal_call(:after_user_register, [%User{id: 123}])
    assert_received :after_user_register_called
  end
end
