defmodule GameServerWeb.Plugs.LoadThemeTest do
  use GameServerWeb.ConnCase, async: false

  alias GameServer.Content
  alias GameServer.Theme.JSONConfig
  alias GameServerWeb.Plugs.LoadTheme

  setup do
    orig =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

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

  test "assigns fallback theme keys into conn when no local theme is configured", %{conn: conn} do
    GameServer.SettingsHelpers.delete(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config
    )

    JSONConfig.reload()

    conn = LoadTheme.call(conn, [])

    assert conn.assigns[:theme]
    assert is_map(conn.assigns[:theme])
    assert conn.assigns[:theme]["title"] == "MISSING_THEME"

    assert conn.assigns[:theme]["tagline"] ==
             "Add host theme config or set GAMEND_CONTENT_THEME_CONFIG"

    assert conn.assigns[:theme]["logo"] == "/images/logo.png"
    assert conn.assigns[:theme]["footer"] in [nil, %{}]
    assert conn.assigns[:theme]["navigation"] in [nil, %{}]
  end

  test "populates theme values from GAMEND_CONTENT_THEME_CONFIG", %{conn: conn} do
    base =
      Path.join(System.tmp_dir!(), "theme_plug_vals_#{System.unique_integer([:positive])}.json")

    File.write!(
      base,
      Jason.encode!(%{"title" => "Test Title", "tagline" => "Test Tag", "logo" => "/logo.png"})
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      base
    )

    JSONConfig.reload()

    on_exit(fn -> File.rm(base) end)

    conn = LoadTheme.call(conn, [])

    assert conn.assigns[:theme]["title"] == "Test Title"
    assert conn.assigns[:theme]["tagline"] == "Test Tag"
    assert conn.assigns[:theme]["logo"] == "/logo.png"
    assert conn.assigns[:theme]["banner"] == "/images/banner.png"
    assert conn.assigns[:theme]["favicon"] == "/favicon.ico"
    assert is_nil(conn.assigns[:theme]["css"])
  end

  test "uses generic missing-theme fallback when provider returns empty map", %{conn: conn} do
    orig_mod = Application.get_env(:game_server_web, :theme_module)
    Application.put_env(:game_server_web, :theme_module, __MODULE__.EmptyThemeMock)

    on_exit(fn ->
      if orig_mod,
        do: Application.put_env(:game_server_web, :theme_module, orig_mod),
        else: Application.delete_env(:game_server_web, :theme_module)
    end)

    defmodule __MODULE__.EmptyThemeMock do
      def get_theme, do: %{}
    end

    conn = LoadTheme.call(conn, [])

    assert conn.assigns[:theme]["title"] == "MISSING_THEME"

    assert conn.assigns[:theme]["tagline"] ==
             "Add host theme config or set GAMEND_CONTENT_THEME_CONFIG"

    assert conn.assigns[:theme]["logo"] == "/images/logo.png"
  end

  # There is one config file now, so the locale can only reach the text through
  # gettext — which means the plug's whole job here is to pass it on. The
  # translation itself is the host's (its gettext tree owns the `theme` domain,
  # so this app's test env cannot resolve it); see the host suite for that.
  test "hands the request locale to the theme provider", %{conn: conn} do
    orig_mod = Application.get_env(:game_server_web, :theme_module)
    Application.put_env(:game_server_web, :theme_module, __MODULE__.LocaleEchoMock)

    on_exit(fn ->
      if orig_mod,
        do: Application.put_env(:game_server_web, :theme_module, orig_mod),
        else: Application.delete_env(:game_server_web, :theme_module)
    end)

    defmodule __MODULE__.LocaleEchoMock do
      def get_theme, do: %{"title" => "no locale"}
      def get_theme(locale), do: %{"title" => "locale=#{locale}"}
    end

    conn = conn |> Plug.Conn.assign(:locale, "es") |> LoadTheme.call([])

    assert conn.assigns[:theme]["title"] == "locale=es"
  end
end
