defmodule Gamend.Release.MetadataTest do
  @moduledoc """
  `Gamend.Release.Metadata`: what a release declares, written at its image's
  build, with the plugins in its plugins directory loaded and none started.
  """
  use ExUnit.Case, async: false

  alias Gamend.Hooks.PluginManager
  alias Gamend.Release.Metadata

  @plugin "metadata_test_plugin"

  setup do
    tmp = Path.join(System.tmp_dir!(), "gs-metadata-#{System.unique_integer([:positive])}")
    root = Path.join(tmp, "modules/plugins")
    ebin = Path.join([root, @plugin, "ebin"])
    File.mkdir_p!(ebin)

    hooks = Module.concat([Gamend, MetadataTestPluginHooks])
    starter = Module.concat([Gamend, MetadataTestPluginApp])

    {:module, ^hooks, hooks_beam, _} =
      Module.create(
        hooks,
        quote do
          def env_vars do
            [
              %{name: "METADATA_TEST_TOKEN", default: "", description: "A token.", secret: true},
              %{name: "METADATA_TEST_ROUNDS", default: 3, description: "Rounds."}
            ]
          end
        end,
        __ENV__
      )

    # Started, it would raise: the metadata must load the plugin, not run it.
    {:module, ^starter, starter_beam, _} =
      Module.create(
        starter,
        quote do
          use Application
          def start(_type, _args), do: raise("a plugin started while writing metadata")
        end,
        __ENV__
      )

    File.write!(Path.join(ebin, "#{hooks}.beam"), hooks_beam)
    File.write!(Path.join(ebin, "#{starter}.beam"), starter_beam)

    app =
      {:application, String.to_atom(@plugin),
       [
         description: ~c"metadata test plugin",
         vsn: ~c"0.1.0",
         modules: [hooks, starter],
         registered: [],
         applications: [:kernel, :stdlib],
         mod: {starter, []},
         env: [hooks_module: hooks]
       ]}

    File.write!(
      Path.join(ebin, "#{@plugin}.app"),
      :io_lib.format(~c"~p.~n", [app]) |> IO.iodata_to_binary()
    )

    # Unloaded, as on a fresh release boot: the plugins dir is where they come from.
    Enum.each([hooks, starter], &unload/1)
    Gamend.SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :plugins_dir, root)

    on_exit(fn ->
      Gamend.SettingsHelpers.delete(:gamend_core, Gamend.ContentSettings, :plugins_dir)
      _ = Application.unload(String.to_atom(@plugin))
      Enum.each([hooks, starter], &unload/1)
      Code.delete_path(ebin)
      _ = PluginManager.reload()
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  defp unload(mod) do
    :code.purge(mod)
    :code.delete(mod)
    :code.purge(mod)
  end

  test "build/0: core's version and every declared setting, the plugins' variables too" do
    metadata = Metadata.build()

    assert metadata["format"] == 1
    assert metadata["gamend_version"] == to_string(Application.spec(:gamend_core, :vsn))

    by_env = Map.new(metadata["settings"], &{&1.env, &1})
    assert %{app: "gamend_core", plugin: nil} = by_env["GAMEND_OAUTH_APPLE_PRIVATE_KEY"]

    assert %{plugin: @plugin, secret: true, doc: "A token."} = by_env["METADATA_TEST_TOKEN"]
    assert %{plugin: @plugin, default: 3, secret: false} = by_env["METADATA_TEST_ROUNDS"]

    refute Enum.any?(Application.started_applications(), &(elem(&1, 0) == :metadata_test_plugin))
  end

  test "write/1 then decode/1 give back the version and the settings", %{tmp: tmp} do
    path = Path.join(tmp, Metadata.file_name())
    ExUnit.CaptureIO.capture_io(fn -> assert :ok = Metadata.write(path) end)

    assert {:ok, %{version: version, settings: settings}} = Metadata.decode(File.read!(path))
    assert version == to_string(Application.spec(:gamend_core, :vsn))
    assert Enum.find(settings, &(&1["env"] == "METADATA_TEST_TOKEN"))["plugin"] == @plugin
  end

  test "decode/1 refuses what is not a metadata file it can read" do
    assert {:ok, %{version: nil, settings: []}} =
             Metadata.decode(~s({"format": 1, "gamend_version": "", "settings": []}))

    for json <- [
          ~s({"format": 2, "gamend_version": "9.0.0", "settings": []}),
          ~s({"gamend_version": "1.0.0", "settings": []}),
          ~s({"format": 1, "settings": {}}),
          "not json",
          "[]"
        ] do
      assert Metadata.decode(json) == {:error, :invalid_metadata}, json
    end
  end
end
