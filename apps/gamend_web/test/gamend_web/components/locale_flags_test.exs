defmodule GamendWeb.LocaleFlagsTest do
  @moduledoc "`\"locale_flags\": false` on the theme's navigation: no national flags."
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias Gamend.ContentSettings
  alias Gamend.SettingsHelpers
  alias Gamend.Theme.JSONConfig
  alias GamendWeb.HostLayoutNavigation

  setup do
    original = SettingsHelpers.get(:gamend_core, ContentSettings, :theme_config)

    on_exit(fn ->
      if original,
        do: SettingsHelpers.put(:gamend_core, ContentSettings, :theme_config, original),
        else: SettingsHelpers.delete(:gamend_core, ContentSettings, :theme_config)

      JSONConfig.reload()
    end)

    :ok
  end

  defp use_theme(navigation) do
    path = Path.join(System.tmp_dir!(), "flags_#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(%{"title" => "Flags", "navigation" => navigation}))
    on_exit(fn -> File.rm(path) end)
    SettingsHelpers.put(:gamend_core, ContentSettings, :theme_config, path)
    JSONConfig.reload()
  end

  defp language_icons do
    render_component(&HostLayoutNavigation.language_dropdown/1,
      locale: "en",
      current_path: "/",
      known_locales: ["en", "fr"]
    )
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".hero-language-solid")
    |> Enum.count()
  end

  test "the switcher draws flags unless the theme says otherwise" do
    use_theme(%{})
    assert language_icons() == 0
  end

  test "false draws a language icon in place of the flag" do
    use_theme(%{"locale_flags" => false})
    assert language_icons() > 0
  end
end
