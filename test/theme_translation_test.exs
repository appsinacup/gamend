defmodule GameServerHost.ThemeTranslationTest do
  @moduledoc """
  The end-to-end guarantee behind the one-config-file design: the site renders
  in the visitor's language without a second copy of the theme.

  This lives in the host suite rather than in `game_server_web` because the
  `theme` gettext domain is the host's — `apps/game_server_web` is a standalone
  library and cannot load `GameServerHost.Gettext`, so its tests can only prove
  that the locale is passed through.
  """

  use ExUnit.Case, async: false

  alias GameServer.Theme.JSONConfig

  setup do
    previous = Application.get_env(:game_server_core, GameServer.ContentSettings)

    Application.put_env(:game_server_core, GameServer.ContentSettings,
      theme_config: Path.join(__DIR__, "../theme/config.json") |> Path.expand()
    )

    JSONConfig.reload()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:game_server_core, GameServer.ContentSettings, previous),
        else: Application.delete_env(:game_server_core, GameServer.ContentSettings)

      JSONConfig.reload()
    end)

    :ok
  end

  defp nav_label(theme), do: get_in(theme, ["navigation", "primary_links", Access.at(0), "label"])
  defp nav_href(theme), do: get_in(theme, ["navigation", "primary_links", Access.at(0), "href"])

  test "the shipped theme renders translated, from a single file" do
    raw = JSONConfig.raw_theme()
    assert nav_label(raw) == "Play", "fixture drifted; this test tracks the first nav link"

    for {locale, expected} <- [
          {"en", "Play"},
          {"ro", "Joacă"},
          {"es", "Jugar"},
          {"de", "Spielen"},
          {"ja", "プレイ"}
        ] do
      assert nav_label(JSONConfig.get_theme(locale)) == expected,
             "#{locale} should translate the nav label"
    end
  end

  test "configuration is identical in every locale" do
    raw = JSONConfig.raw_theme()

    for locale <- Gettext.known_locales(GameServerHost.Gettext) do
      theme = JSONConfig.get_theme(locale)

      assert Map.get(theme, "theme_color") == Map.get(raw, "theme_color"),
             "theme_color changed under #{locale}"

      assert nav_href(theme) == nav_href(raw), "a nav href changed under #{locale}"
    end
  end

  test "every locale translates the theme, not just a favoured few" do
    raw = JSONConfig.raw_theme()

    untranslated =
      for locale <- Gettext.known_locales(GameServerHost.Gettext),
          locale != "en",
          nav_label(JSONConfig.get_theme(locale)) == nav_label(raw),
          do: locale

    assert untranslated == [],
           "these locales fall back to English for the nav label: #{inspect(untranslated)}"
  end
end
