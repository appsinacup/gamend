defmodule GameServer.ThemeI18nTest do
  @moduledoc """
  The theme used to be one whole JSON file per locale. Two thirds of each copy
  was structure rather than text, and they drifted: a `theme_color` added to
  English never reached the other 29, so every non-English visitor silently got
  the fallback colour.

  These lock in the property that makes that impossible — configuration is not
  translatable, so it cannot vary by locale at all.
  """

  use ExUnit.Case, async: false

  alias GameServer.Theme.JSONConfig
  alias GameServer.Theme.Translatable

  # The suite runs from the web app, so repo-relative paths must be resolved
  # against the umbrella root rather than the working directory.
  @repo_root Path.expand("../../../..", __DIR__)

  @config %{
    "title" => "Gamend",
    "theme_color" => %{"light" => "#ffffff", "dark" => "#1a1a2e"},
    "navigation" => %{
      "primary_links" => [
        %{"label" => "Play", "href" => "/play", "icon" => "hero-play-solid"},
        %{"label" => "Social", "href" => "/social"}
      ]
    },
    "pages" => %{
      "home" => %{
        "hero" => %{
          "title" => "Gamend",
          "text" => "Open source.",
          "image" => %{"alt" => "Gamend", "light" => "/images/banner.png"},
          "image_position_desktop" => "left"
        }
      }
    }
  }

  describe "what counts as text" do
    test "text keys are translatable" do
      for key <- ~w(label title text tagline description alt site_message cta subtitle) do
        assert Translatable.text?(key), "#{key} should be translatable"
      end
    end

    test "configuration keys are not" do
      for key <- ~w(href url icon style light dark image_position_desktop media_width slug) do
        refute Translatable.text?(key), "#{key} must never be translated"
      end
    end

    test "an atom key works the same as a string" do
      assert Translatable.text?(:label)
      refute Translatable.text?(:href)
    end
  end

  describe "walking a config" do
    test "rewrites text and leaves configuration untouched" do
      walked = Translatable.walk(@config, fn text -> "[#{text}]" end)

      assert get_in(walked, ["navigation", "primary_links", Access.at(0), "label"]) == "[Play]"
      assert get_in(walked, ["pages", "home", "hero", "text"]) == "[Open source.]"
      assert get_in(walked, ["pages", "home", "hero", "image", "alt"]) == "[Gamend]"

      # The whole point: none of this can be changed by a translation.
      assert get_in(walked, ["theme_color", "light"]) == "#ffffff"
      assert get_in(walked, ["theme_color", "dark"]) == "#1a1a2e"
      assert get_in(walked, ["navigation", "primary_links", Access.at(0), "href"]) == "/play"

      assert get_in(walked, ["navigation", "primary_links", Access.at(0), "icon"]) ==
               "hero-play-solid"

      assert get_in(walked, ["pages", "home", "hero", "image", "light"]) == "/images/banner.png"
      assert get_in(walked, ["pages", "home", "hero", "image_position_desktop"]) == "left"
    end

    test "a blank string is left alone rather than offered for translation" do
      walked = Translatable.walk(%{"site_message" => "   "}, fn _ -> "translated" end)
      assert walked["site_message"] == "   "
    end
  end

  describe "extraction" do
    test "collects every translatable string once, and no configuration" do
      strings = Translatable.strings(@config)

      assert "Play" in strings
      assert "Social" in strings
      assert "Open source." in strings

      refute "#ffffff" in strings
      refute "/play" in strings
      refute "hero-play-solid" in strings
      refute "left" in strings

      # "Gamend" is both the site title and the hero title — one msgid.
      assert Enum.count(strings, &(&1 == "Gamend")) == 1
    end

    test "no configuration value can reach a translator" do
      config_values = ["#ffffff", "#1a1a2e", "/play", "/social", "hero-play-solid", "left"]
      strings = Translatable.strings(@config)

      for value <- config_values do
        refute value in strings, "#{value} is configuration and must not be extracted"
      end
    end
  end

  describe "the real theme config" do
    setup do
      previous = Application.get_env(:game_server_core, GameServer.ContentSettings)

      Application.put_env(:game_server_core, GameServer.ContentSettings,
        theme_config: Path.join(@repo_root, "theme/config.json")
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

    test "loads as a single file, with configuration intact" do
      raw = JSONConfig.raw_theme()

      assert map_size(raw) > 0, "theme/config.json should load"
      assert %{"light" => _, "dark" => _} = Map.get(raw, "theme_color")
    end

    test "translating never disturbs configuration" do
      raw = JSONConfig.raw_theme()

      for locale <- ["en", "ro", "el", "zz"] do
        translated = JSONConfig.get_theme(locale)

        assert Map.get(translated, "theme_color") == Map.get(raw, "theme_color"),
               "theme_color changed under locale #{locale}"

        assert get_in(translated, ["navigation", "primary_links", Access.at(0), "href"]) ==
                 get_in(raw, ["navigation", "primary_links", Access.at(0), "href"]),
               "a href changed under locale #{locale}"
      end
    end

    test "an unknown locale falls back to the source strings" do
      assert JSONConfig.get_theme("zz") == JSONConfig.raw_theme()
    end
  end

  describe "no per-locale config files remain" do
    test "the theme is one file" do
      # The failure this replaces: 29 copies, each free to drift from the base.
      assert Path.wildcard(Path.join(@repo_root, "theme/config.*.json")) == [],
             "per-locale theme configs are gone; translations live in priv/gettext"

      assert File.exists?(Path.join(@repo_root, "theme/config.json"))
    end

    test "there is no second, example copy of it" do
      # `modules/example_config.json` was a stale duplicate nothing loaded, so
      # it drifted from the real theme and misled anyone who edited it.
      refute File.exists?(Path.join(@repo_root, "modules/example_config.json"))
    end
  end
end
