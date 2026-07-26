defmodule GameServerWeb.OnMount.ThemeTest do
  use ExUnit.Case, async: false

  alias GameServer.Theme.JSONConfig
  alias GameServerWeb.GettextSync
  alias GameServerWeb.OnMount.Theme
  alias Phoenix.LiveView

  setup do
    orig_theme_config =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

    orig_locale = Gettext.get_locale(GameServerWeb.Gettext)

    JSONConfig.reload()

    on_exit(fn ->
      if orig_theme_config do
        GameServer.SettingsHelpers.put(
          :game_server_core,
          GameServer.ContentSettings,
          :theme_config,
          orig_theme_config
        )
      else
        GameServer.SettingsHelpers.delete(
          :game_server_core,
          GameServer.ContentSettings,
          :theme_config
        )
      end

      GettextSync.put_locale(orig_locale)
      JSONConfig.reload()
    end)

    :ok
  end

  test "assigns the theme on each mount, whatever the locale" do
    base =
      Path.join(System.tmp_dir!(), "theme_on_mount_#{System.unique_integer([:positive])}.json")

    File.write!(base, Jason.encode!(%{"title" => "Play"}))

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      base
    )

    JSONConfig.reload()

    on_exit(fn -> File.rm(base) end)

    GettextSync.put_locale("id")
    {:cont, id_socket} = Theme.on_mount(:mount_theme, %{}, %{}, %LiveView.Socket{})

    GettextSync.put_locale("en")
    {:cont, en_socket} = Theme.on_mount(:mount_theme, %{}, %{}, %LiveView.Socket{})

    # One config file for every locale, so both mounts see the same source
    # text; translating it is gettext's job, exercised in the host suite.
    assert id_socket.assigns.theme["title"] == "Play"
    assert en_socket.assigns.theme["title"] == "Play"
  end
end
