defmodule GamendWeb.PresentationPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias GamendWeb.PresentationPage

  describe "page_for_path/2" do
    test "returns configured page by path" do
      theme = %{
        "pages" => %{
          "home" => %{"path" => "/", "hero" => %{"title" => "Home"}},
          "brand" => %{"path" => "/brand", "hero" => %{"title" => "Brand"}}
        }
      }

      assert %{"key" => "brand", "hero" => %{"title" => "Brand"}} =
               PresentationPage.page_for_path(theme, "/brand")
    end

    test "returns nil for missing page path" do
      assert is_nil(PresentationPage.page_for_path(%{"pages" => %{}}, "/missing"))
    end
  end

  describe "rich_text/1" do
    test "returns safe HTML for plain text" do
      result = PresentationPage.rich_text("Hello world")
      assert {:safe, _} = result
      assert Phoenix.HTML.safe_to_string(result) == "Hello world"
    end

    test "converts single **bold** to <strong>" do
      result = PresentationPage.rich_text("Hello **world**")
      html = Phoenix.HTML.safe_to_string(result)
      assert html == "Hello <strong>world</strong>"
    end

    test "converts multiple **bold** groups" do
      result =
        PresentationPage.rich_text(
          "**Open source** Elixir game server for **real-time** multiplayer games."
        )

      html = Phoenix.HTML.safe_to_string(result)

      assert html ==
               "<strong>Open source</strong> Elixir game server for <strong>real-time</strong> multiplayer games."
    end

    test "converts italic and safe links" do
      result = PresentationPage.rich_text("Read *more* in the [docs](/docs/setup).")
      html = Phoenix.HTML.safe_to_string(result)

      assert html =~ "<em>more</em>"
      assert html =~ ~s(<a href="/docs/setup" class="link link-primary">docs</a>)
    end

    test "escapes HTML entities before applying bold" do
      result = PresentationPage.rich_text("**<script>**alert**</script>**")
      html = Phoenix.HTML.safe_to_string(result)
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
      assert html =~ "<strong>"
    end

    test "returns empty safe HTML for nil" do
      result = PresentationPage.rich_text(nil)
      assert {:safe, _} = result
      assert Phoenix.HTML.safe_to_string(result) == ""
    end

    test "returns empty safe HTML for empty string" do
      result = PresentationPage.rich_text("")
      assert {:safe, _} = result
      assert Phoenix.HTML.safe_to_string(result) == ""
    end
  end

  describe "page/1" do
    test "supports page-level section height defaults" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{"title" => "Demo"},
            "sections_height" => "half",
            "sections" => [
              %{"title" => "One", "text" => "First", "icon" => "hero-home-solid"}
            ]
          },
          background_icons: [],
          full_bleed_hero: false
        )

      assert html =~ "min-h-[calc(50svh-2.5rem)]"

      assert html =~
               ~s|class="grid w-full gap-6 md:gap-x-8 md:gap-y-4 items-center min-h-[calc(50svh-2.5rem)] py-8 md:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]"|

      assert html =~
               ~s|class="flex flex-col gap-4 md:justify-center md:gap-5 md:pt-6 md:min-h-48 row-start-2 md:row-start-1 md:col-start-2 text-center items-center"|
    end

    test "renders animated scroll cue when sections follow hero" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{"title" => "Demo"},
            "sections" => [
              %{"title" => "One", "text" => "First", "icon" => "hero-home-solid"}
            ]
          },
          background_icons: [],
          full_bleed_hero: false
        )

      assert html =~ ~s(href="#more-content")
      assert html =~ ~s(aria-label="Scroll to content")
      assert html =~ "motion-safe:animate-bounce"

      assert html =~
               ~s|class="grid w-full gap-6 md:gap-x-8 md:gap-y-4 items-center py-8 md:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]"|

      refute html =~ "min-h-[calc(100svh-5rem)]"
    end

    test "renders background icons behind whole page content" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{"title" => "Demo"},
            "sections" => [
              %{"title" => "One", "text" => "First", "icon" => "hero-home-solid"}
            ]
          },
          background_icons: ["hero-trophy-solid"],
          full_bleed_hero: false
        )

      assert html =~ ~s(class="relative overflow-hidden")
      assert html =~ ~s(class="absolute inset-0 overflow-hidden pointer-events-none z-[1]")
      assert html =~ ~s(class="absolute left-0 top-0 h-dvh w-full")
      assert html =~ "transform: translateY(0dvh);"
      assert html =~ "transform: translateY(100dvh);"

      assert html =~
               ~s(class="relative z-10 mx-auto grid w-full gap-y-4 px-4 sm:px-6 lg:px-8 max-w-2xl md:max-w-3xl lg:max-w-4xl xl:max-w-6xl")
    end

    test "does not render scroll cue when no sections follow hero" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{"hero" => %{"title" => "Demo"}},
          background_icons: [],
          full_bleed_hero: false
        )

      refute html =~ ~s(aria-label="Scroll to content")
    end

    test "hero media is visual only" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{
              "title" => "Demo",
              "image" => %{"light" => "/images/banner.png", "alt" => "Demo banner"}
            }
          },
          background_icons: [],
          full_bleed_hero: false
        )

      refute html =~ "<a"
      refute html =~ "motion-safe:hover:scale"
      assert html =~ "max-h-[58dvh]"
    end

    test "hero media can use section sizing" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{
              "title" => "Demo",
              "image" => %{"light" => "/images/banner.png", "alt" => "Demo banner"},
              "media_size" => "section"
            }
          },
          background_icons: [],
          full_bleed_hero: false
        )

      assert html =~ "aspect-square max-h-[42dvh]"
      refute html =~ "max-h-[58dvh]"
    end

    test "media supports light and dark image variants" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{
              "title" => "Demo",
              "image" => %{
                "light" => "/images/fullscreen.png",
                "dark" => "/images/fullscreen_dark.png",
                "alt" => "Demo fullscreen"
              }
            }
          },
          background_icons: [],
          full_bleed_hero: false
        )

      # An image that exists in the host's static dir comes back from
      # `SRI.versioned_path/1` with a `?v=` cache-buster, so the src is only
      # the path up to the query.
      assert html =~ ~r{src="/images/fullscreen\.png(\?v=[^"]*)?"}
      assert html =~ ~r{src="/images/fullscreen_dark\.png(\?v=[^"]*)?"}
      assert html =~ ~s(alt="Demo fullscreen")
      assert html =~ "[[data-theme=dark]_&amp;]:hidden"
      assert html =~ "hidden [[data-theme=dark]_&amp;]:block"
    end

    test "image sections use image-height text frame" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{"title" => "Demo"},
            "sections" => [
              %{
                "title" => "Image Section",
                "text" => "Short text",
                "image" => %{"light" => "/images/logo.png", "alt" => "Logo"},
                "buttons" => [%{"label" => "Open", "href" => "/open"}]
              }
            ]
          },
          background_icons: [],
          full_bleed_hero: false
        )

      assert html =~ "md:min-h-[min(42dvh,24rem)]"
      assert html =~ ~s|class="pt-1 md:pt-2"|
      refute html =~ "md:flex-1"
    end

    test "icon media has no border and is not clickable" do
      html =
        render_component(&PresentationPage.section/1,
          section: %{
            "title" => "One",
            "text" => "First",
            "icon" => "hero-home-solid"
          }
        )

      refute html =~ "<a"
      refute html =~ "border-base"
      assert html =~ "rounded-lg bg-base-100/70"
      refute html =~ "motion-safe:hover:scale"
    end

    test "compact section height uses content size" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{"title" => "Demo"},
            "sections" => [
              %{
                "title" => "One",
                "text" => "First",
                "icon" => "hero-home-solid",
                "height" => "compact"
              }
            ]
          },
          background_icons: [],
          full_bleed_hero: false
        )

      assert html =~
               ~s|class="grid w-full gap-6 md:gap-x-8 md:gap-y-4 items-center py-8 md:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]"|

      assert html =~
               ~s|md:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]|

      refute html =~ "min-h-[18rem]"
    end

    test "full section height uses viewport height" do
      html =
        render_component(&PresentationPage.page/1,
          page: %{
            "hero" => %{"title" => "Demo"},
            "sections" => [
              %{
                "title" => "One",
                "text" => "First",
                "icon" => "hero-home-solid",
                "height" => "full"
              }
            ]
          },
          background_icons: [],
          full_bleed_hero: false
        )

      assert html =~ "min-h-[calc(100svh-5rem)] py-12"
    end
  end
end
