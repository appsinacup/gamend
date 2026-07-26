defmodule GameServerWeb.ThemeLiveTest do
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GameServer.Content
  alias GameServer.Theme.JSONConfig

  test "LiveView pages render without errors when GAMEND_CONTENT_THEME_CONFIG is unset", %{
    conn: conn
  } do
    # Ensure GAMEND_CONTENT_THEME_CONFIG unset so no theme is loaded
    orig =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

    GameServer.SettingsHelpers.delete(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config
    )

    JSONConfig.reload()
    Content.reload()

    on_exit(fn ->
      if orig,
        do:
          GameServer.SettingsHelpers.put(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config,
            orig
          ),
        else:
          GameServer.SettingsHelpers.delete(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config
          )

      JSONConfig.reload()
      Content.reload()
    end)

    {:ok, _lv, html} = live(conn, "/leaderboards")

    # Page should render without crashing even with no theme
    assert html =~ "<html"
  end
end
