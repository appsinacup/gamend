defmodule GamendWeb.Components.PresentationPageSrcsetTest do
  @moduledoc """
  `"widths": [...]` on a config image opts it into a responsive `srcset`. The
  variants are addressed by convention (`foo.png` + 480 is `foo-480.png`), so
  nothing but this list connects the config to the files on disk — and a wrong
  guess is a broken image rather than a heavy one.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.PresentationPage

  @fixture "/images/media-fixture.png"
  @webp_fixture "/images/media-fixture.webp"

  # `priv/static` is generated, so it is gitignored wholesale — a fixture
  # committed there reaches nobody else's checkout, and every positive case
  # here fails on CI with no srcset. The variant only has to pass
  # `File.regular?`, so the test writes it and takes it away again.
  @fixture_files ["media-fixture.png", "media-fixture-4.png"]
  @webp_fixture_files ["media-fixture.webp", "media-fixture-4.webp"]

  # 1x1 transparent PNG. Never decoded — the component only checks the file is
  # there — but a real one keeps anything that opens it honest.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk" <>
           "YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
       )

  # 12x8 lossy WebP. This one IS decoded: presentation art is WebP, and a
  # source whose dimensions the component cannot read gets no full-size srcset
  # candidate — which is the whole bug these tests guard.
  @webp Base.decode64!(
          "UklGRjwAAABXRUJQVlA4IDAAAADQAQCdASoMAAgAAUAmJaACdLoB+AADsAD+" <>
            "8ut//NgVzXPv9//S4P0uD9Lg/9KQAAA="
        )

  setup do
    # Written where the component looks them up, not where the source tree
    # keeps them, so a copied (rather than symlinked) priv still works.
    dir = Application.app_dir(:gamend_web, "priv/static/images")
    File.mkdir_p!(dir)

    for name <- @fixture_files, do: File.write!(Path.join(dir, name), @png)
    for name <- @webp_fixture_files, do: File.write!(Path.join(dir, name), @webp)

    on_exit(fn ->
      for name <- @fixture_files ++ @webp_fixture_files, do: File.rm(Path.join(dir, name))
    end)

    :ok
  end

  defp render_media(item, variant \\ "section") do
    render_component(&PresentationPage.media/1, item: item, variant: variant)
  end

  test "no widths means no srcset, exactly as before the attribute existed" do
    html = render_media(%{"image" => %{"light" => @fixture, "alt" => "x"}})

    assert html =~ "<img"
    refute html =~ "srcset"
    refute html =~ "sizes"
  end

  test "a declared width whose file exists lands in the srcset with its descriptor" do
    html = render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4]}})

    assert html =~ "srcset="
    assert html =~ "/images/media-fixture-4.png"
    assert html =~ "4w"
  end

  test "a declared width whose file is missing is dropped, not emitted as a 404" do
    # A 404 inside a srcset is not a graceful fallback to `src` — it is a broken
    # image on whichever viewport picked that candidate.
    html =
      render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4, 9999]}})

    assert html =~ "/images/media-fixture-4.png"
    refute html =~ "media-fixture-9999.png"
  end

  test "every width missing leaves the img with no srcset at all" do
    html = render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [7777]}})

    assert html =~ "<img"
    refute html =~ "srcset"
    refute html =~ "sizes"
  end

  test "the full-size source is itself a candidate, at its declared width" do
    # Once srcset carries `w` descriptors the browser ignores `src` when
    # choosing, so a list of downscaled variants alone caps the image at the
    # widest variant — a 2x viewport then upscales it and it looks blurry.
    html =
      render_media(%{
        "image" => %{"light" => @fixture, "alt" => "x", "widths" => [4], "width" => 40}
      })

    assert html =~ "/images/media-fixture-4.png"
    assert html =~ ~r{/images/media-fixture\.png[^,"]* 40w}
  end

  test "a WebP source's own dimensions are read, so it needs no declared width" do
    html = render_media(%{"image" => %{"light" => @webp_fixture, "alt" => "x", "widths" => [4]}})

    assert html =~ "/images/media-fixture-4.webp"
    assert html =~ ~r{/images/media-fixture\.webp[^,"]* 12w}
  end

  test "a source no wider than its widest variant is not appended" do
    # `mix host.responsive_images` refuses to upscale, so this pairing only
    # happens when the config over-declares — and re-listing the source under a
    # descriptor it cannot honour would make the browser pick a soft candidate.
    html =
      render_media(%{
        "image" => %{"light" => @fixture, "alt" => "x", "widths" => [4], "width" => 3}
      })

    assert html =~ "/images/media-fixture-4.png"
    refute html =~ " 3w"
  end

  test "sizes describes the slot, so the browser can pick before layout" do
    # Without `sizes` the browser assumes 100vw and takes the largest candidate,
    # which throws away the point of shipping variants at all.
    section = render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4]}})

    hero =
      render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4]}}, "hero")

    # The column's real width, not a share of the viewport: the content box
    # stops growing at `xl:max-w-6xl`, so a "third" column tops out at 423px.
    assert section =~
             ~s{sizes="(min-width: 1280px) 423px, (min-width: 1024px) 320px, } <>
               ~s{(min-width: 768px) 276px, (min-width: 672px) 624px, calc(100vw - 32px)"}

    assert hero =~
             ~s{sizes="(min-width: 1280px) 504px, (min-width: 1024px) 376px, } <>
               ~s{(min-width: 768px) 336px, (min-width: 672px) 608px, calc(100vw - 48px)"}
  end

  test "sizes follows the column's share and the page's two-up grid" do
    item = fn width ->
      %{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4]}, "media_width" => width}
    end

    wide = render_media(item.("wide"))
    full = render_media(item.("third"), "full")

    two_up =
      render_component(&PresentationPage.media/1,
        item: item.("third"),
        variant: "section",
        columns: 2
      )

    assert wide =~ "(min-width: 1280px) 608px"
    assert full =~ "(min-width: 1280px) 1088px"
    # Two sections a row: each is half the box less the 16px gap between them.
    assert two_up =~ "(min-width: 1280px) 202px"
    # Below `md` both grids are one column, so the phone rule is unchanged.
    assert two_up =~ "calc(100vw - 32px)"
  end

  test "a section image's box takes the image's shape when its size is known" do
    known = render_media(%{"image" => %{"light" => @webp_fixture, "alt" => "x"}})
    unknown = render_media(%{"image" => %{"light" => "/images/not-on-disk.png", "alt" => "x"}})

    # A square box around 16:9 art letterboxes it, and audits flag the
    # mismatch as a distorted image.
    assert known =~ ~s{width="12" height="8"}
    refute known =~ "aspect-square"
    # With no size to go on, the square still holds the slot before load.
    assert unknown =~ "aspect-square"
  end

  test "an explicit sizes in the config wins over the per-slot default" do
    html =
      render_media(%{
        "image" => %{"light" => @fixture, "alt" => "x", "widths" => [4], "sizes" => "42vw"}
      })

    assert html =~ "42vw"
    refute html =~ "calc(100vw - 32px)"
  end

  test "the light/dark pair gets a srcset per theme, from each one's own variants" do
    html =
      render_media(%{
        "image" => %{
          "light" => @fixture,
          # No `-4` twin on disk for this one, so only the light img is
          # responsive — the dark img must not borrow the light srcset.
          "dark" => "/images/media-missing-dark.png",
          "alt" => "x",
          "widths" => [4]
        }
      })

    assert html =~ "/images/media-fixture-4.png"
    refute html =~ "media-missing-dark-4.png"
  end

  test "media_visual/1 still tolerates a partial image map" do
    # It is public, and a host may build the map by hand. Missing srcset keys
    # must not be a KeyError.
    html =
      render_component(&PresentationPage.media_visual/1,
        image: %{light: @fixture, dark: nil, alt: "", width: nil, height: nil},
        variant: "hero",
        size: "hero"
      )

    assert html =~ "<img"
    refute html =~ "srcset"
  end
end
