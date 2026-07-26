defmodule GameServer.Theme.JSONConfigTest do
  use ExUnit.Case, async: false

  alias GameServer.Content
  alias GameServer.Theme.JSONConfig

  setup do
    # ensure any global env change is reset after
    orig =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

    # Clear theme cache before each test so env var changes take effect
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

    :ok
  end

  test "loads the config file itself, with no locale suffix" do
    base = Path.join(System.tmp_dir!(), "theme_test_#{System.unique_integer([:positive])}.json")

    File.write!(base, Jason.encode!(%{"title" => "My Test", "logo" => "/theme/logo.png"}))
    on_exit(fn -> File.rm(base) end)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      base
    )

    assert JSONConfig.get_theme() == %{"title" => "My Test", "logo" => "/theme/logo.png"}
  end

  test "a locale-suffixed file is ignored — one config, translated via gettext" do
    base =
      Path.join(System.tmp_dir!(), "theme_test_base_#{System.unique_integer([:positive])}.json")

    es_path = String.trim_trailing(base, ".json") <> ".es.json"

    File.write!(base, Jason.encode!(%{"title" => "English Title", "logo" => "/en.png"}))
    # Left over from the per-locale era: it must have no effect at all.
    File.write!(es_path, Jason.encode!(%{"title" => "Titulo ES", "logo" => "/es.png"}))

    on_exit(fn ->
      File.rm(base)
      File.rm(es_path)
    end)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      base
    )

    assert %{"title" => "English Title", "logo" => "/en.png"} = JSONConfig.get_theme("es")
    assert %{"title" => "English Title", "logo" => "/en.png"} = JSONConfig.get_theme()
  end

  test "returns empty map when GAMEND_CONTENT_THEME_CONFIG points to missing file" do
    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      "nonexistent.json"
    )

    theme = JSONConfig.get_theme()
    assert theme == %{}
  end

  test "returns an empty theme when GAMEND_CONTENT_THEME_CONFIG is unset in standalone web mode" do
    GameServer.SettingsHelpers.delete(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config
    )

    assert JSONConfig.get_theme() == %{}
  end

  test "treats blank GAMEND_CONTENT_THEME_CONFIG as unset in standalone web mode" do
    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      ""
    )

    assert JSONConfig.get_theme() == %{}
  end

  test "runtime_path reports only the env override when no standalone default is configured" do
    GameServer.SettingsHelpers.delete(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config
    )

    assert JSONConfig.runtime_path() == nil
    assert JSONConfig.active_path() == nil
  end

  test "normalizes relative asset paths from runtime JSON" do
    base =
      Path.join(System.tmp_dir!(), "theme_test_paths_#{System.unique_integer([:positive])}.json")

    json =
      Jason.encode!(%{
        "description" => "Path Test",
        "title" => "Path Test",
        "css" => "custom/example_theme.css",
        "logo" => "custom/example_logo.png",
        "banner" => "custom/example_banner.png",
        "banner_link" => "/docs/setup",
        "favicon" => "custom/favicon.ico",
        "changelog" => "/CHANGELOG.md",
        "roadmap" => "/ROADMAP.md",
        "blog" => "/blog"
      })

    File.write!(base, json)

    on_exit(fn -> File.rm(base) end)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      base
    )

    theme = JSONConfig.get_theme()

    assert Map.get(theme, "description") == "Path Test"
    assert Map.get(theme, "title") == "Path Test"
    assert Map.get(theme, "css") == "/custom/example_theme.css"
    assert Map.get(theme, "logo") == "/custom/example_logo.png"
    assert Map.get(theme, "banner") == "/custom/example_banner.png"
    assert Map.get(theme, "banner_link") == "/docs/setup"
    assert Map.get(theme, "favicon") == "/custom/favicon.ico"
    assert Map.get(theme, "changelog") == "/CHANGELOG.md"
    assert Map.get(theme, "roadmap") == "/ROADMAP.md"
    assert Map.get(theme, "blog") == "/blog"
  end
end
