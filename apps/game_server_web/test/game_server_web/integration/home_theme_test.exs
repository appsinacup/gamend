defmodule GameServerWeb.HomeThemeTest do
  use GameServerWeb.ConnCase, async: true

  alias GameServer.Content
  alias GameServer.Theme.JSONConfig

  test "home page renders without errors when runtime theme has empty values", %{conn: conn} do
    # Empty values — no merging with packaged defaults
    base =
      Path.join(System.tmp_dir!(), "theme_test_home_#{System.unique_integer([:positive])}.json")

    File.write!(base, Jason.encode!(%{"title" => "", "tagline" => ""}))

    orig =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      base
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
      File.rm(base)
    end)

    resp = get(conn, "/") |> html_response(200)

    # Page should render without crashing
    assert resp =~ "<html"
    assert resp =~ "<title"
  end
end
