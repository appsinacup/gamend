defmodule GamendWeb.Components.PresentationPageOverlayTest do
  @moduledoc """
  Presentation images from a project's static overlay. The page has to link
  the project's file and only the variants cut from it: never the engine's
  srcset variants, generated WebP or hash for a file the project replaced.

  Not async: the overlay is a global setting, cached.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.PresentationPage
  alias GamendWeb.ProjectStatic

  # 12x8 lossy WebP, decoded for its dimensions.
  @webp Base.decode64!(
          "UklGRjwAAABXRUJQVlA4IDAAAADQAQCdASoMAAgAAUAmJaACdLoB+AADsAD+" <>
            "8ut//NgVzXPv9//S4P0uD9Lg/9KQAAA="
        )

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:gamend_core, Gamend.ContentSettings)
    overlay = Path.join(tmp, "static")
    File.mkdir_p!(Path.join(overlay, "images"))

    Application.put_env(
      :gamend_core,
      Gamend.ContentSettings,
      Keyword.put(previous || [], :static_dirs, [overlay])
    )

    ProjectStatic.reset()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, Gamend.ContentSettings, previous),
        else: Application.delete_env(:gamend_core, Gamend.ContentSettings)

      ProjectStatic.reset()
    end)

    %{overlay: overlay, name: "overlay-#{System.unique_integer([:positive])}"}
  end

  defp builtin!(rel, content) do
    path = Path.join(Application.app_dir(:gamend_web, "priv/static"), rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp own!(overlay, rel, content) do
    path = Path.join(overlay, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp render_media(item), do: render_component(&PresentationPage.media/1, item: item)

  test "an overlay image is measured and linked from the overlay", %{overlay: o, name: n} do
    own!(o, "images/#{n}.webp", @webp)
    own!(o, "images/#{n}-4.webp", @webp)

    html = render_media(%{"image" => %{"light" => "/images/#{n}.webp", "widths" => [4, 8]}})

    assert html =~ ~s(width="12")
    assert html =~ "/images/#{n}-4.webp"
    assert html =~ ~r{/images/#{n}\.webp[^,"]* 12w}
    # Declared, never cut: no candidate that would 404.
    refute html =~ "#{n}-8.webp"
  end

  test "the engine's variants of a replaced image are not offered", %{overlay: o, name: n} do
    builtin!("images/#{n}.webp", "engine art")
    builtin!("images/#{n}-4.webp", "engine art, smaller")
    own!(o, "images/#{n}.webp", @webp)

    html = render_media(%{"image" => %{"light" => "/images/#{n}.webp", "widths" => [4]}})

    refute html =~ "#{n}-4.webp"
    refute html =~ "srcset"
  end

  test "the engine's generated WebP of a replaced PNG is not swapped in", %{overlay: o, name: n} do
    builtin!("images/#{n}.png", "engine png")
    builtin!("images/generated/#{n}.webp", "engine webp")
    own!(o, "images/#{n}.png", "project png")

    html = render_media(%{"image" => %{"light" => "/images/#{n}.png"}})

    assert html =~ "/images/#{n}.png?v="
    refute html =~ "/images/generated/#{n}.webp"

    project_hash = :crypto.hash(:sha384, "project png") |> Base.encode64()
    assert html =~ URI.encode_query(%{"v" => project_hash})
  end

  test "a cached page picks up variants cut after it was rendered", %{overlay: o, name: n} do
    own!(o, "images/#{n}.webp", @webp)

    page = %{
      "path" => "/#{n}",
      "hero" => %{
        "title" => "Hero",
        "image" => %{"light" => "/images/#{n}.webp", "alt" => "x", "widths" => [4]}
      }
    }

    before = page |> PresentationPage.cached_body([], "en", "/#{n}") |> IO.iodata_to_binary()
    refute before =~ "#{n}-4.webp"

    own!(o, "images/#{n}-4.webp", @webp)
    ProjectStatic.bump_generation()

    later = page |> PresentationPage.cached_body([], "en", "/#{n}") |> IO.iodata_to_binary()
    assert later =~ "#{n}-4.webp"
  end
end
