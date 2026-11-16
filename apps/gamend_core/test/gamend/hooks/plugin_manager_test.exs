defmodule Gamend.Hooks.PluginManagerTest do
  use Gamend.DataCase, async: false

  alias Gamend.Hooks.PluginManager

  test "reload loads OTP plugin apps and call_rpc routes by plugin name" do
    tmp = Path.join(System.tmp_dir!(), "gs-plugin-mgr-#{System.unique_integer([:positive])}")
    plugin_root = Path.join(tmp, "modules/plugins")
    plugin_name = "test_plugin_mgr"
    plugin_dir = Path.join(plugin_root, plugin_name)
    ebin_dir = Path.join(plugin_dir, "ebin")

    File.mkdir_p!(ebin_dir)

    Application.put_env(:gamend, :plugin_mgr_test_pid, self())

    hook_mod = Module.concat([Gamend, TestPluginMgrHook])

    {:module, ^hook_mod, beam, _} =
      Module.create(
        hook_mod,
        quote do
          use Gamend.Hooks

          @impl true
          def before_stop do
            if pid = Application.get_env(:gamend, :plugin_mgr_test_pid) do
              send(pid, {:before_stop, :test_plugin_mgr})
            end

            :ok
          end

          def echo(a), do: a
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

    on_exit(fn ->
      Gamend.SettingsHelpers.delete(
        :gamend_core,
        Gamend.ContentSettings,
        :plugins_dir
      )

      Application.delete_env(:gamend, :plugin_mgr_test_pid)
      _ = PluginManager.reload()
    end)

    _ = PluginManager.reload()

    assert {:ok, plugin} = PluginManager.lookup(plugin_name)
    assert plugin.status == :ok
    assert plugin.hooks_module == hook_mod

    assert {:ok, [1, 2, 3]} = PluginManager.call_rpc(plugin_name, "echo", [[1, 2, 3]])

    _ = PluginManager.reload()
    assert_received {:before_stop, :test_plugin_mgr}
  end

  # A release's code server is embedded for the life of the VM, so the mode is
  # passed in rather than switched: what matters is that a beam sitting on a
  # plugin's path, unloaded, is loaded in embedded mode and left alone in
  # interactive mode, where the first call would load it anyway.
  describe "load_beams/2" do
    setup do
      ebin =
        Path.join(System.tmp_dir!(), "gs-plugin-beams-#{System.unique_integer([:positive])}")

      File.mkdir_p!(ebin)

      mod = Module.concat([Gamend, "EmbeddedPluginBeam#{System.unique_integer([:positive])}"])
      {:module, ^mod, beam, _} = Module.create(mod, quote(do: def(hi, do: :hi)), __ENV__)
      File.write!(Path.join(ebin, "#{mod}.beam"), beam)

      # Unloaded, as it would be on a fresh release boot.
      :code.purge(mod)
      :code.delete(mod)
      :code.purge(mod)

      on_exit(fn ->
        :code.purge(mod)
        :code.delete(mod)
        File.rm_rf!(ebin)
      end)

      %{ebin: ebin, mod: mod}
    end

    test "embedded mode loads every beam on the plugin's paths", %{ebin: ebin, mod: mod} do
      assert :code.is_loaded(mod) == false

      assert :ok = PluginManager.load_beams([ebin], :embedded)

      assert {:file, _} = :code.is_loaded(mod)
      assert mod.hi() == :hi
      # Idempotent: a reload over loaded modules is not an error.
      assert :ok = PluginManager.load_beams([ebin], :embedded)
    end

    test "interactive mode leaves loading to the first call", %{ebin: ebin, mod: mod} do
      assert :ok = PluginManager.load_beams([ebin], :interactive)
      assert :code.is_loaded(mod) == false
    end

    test "a beam that will not load fails the plugin", %{ebin: ebin} do
      File.write!(Path.join(ebin, "Elixir.Gamend.NotABeam.beam"), "garbage")

      assert {:error, {:module_load_failed, Gamend.NotABeam, _}} =
               PluginManager.load_beams([ebin], :embedded)
    end
  end
end
