defmodule GamendWeb.NavTestProvider do
  @moduledoc false
  # Dynamic nav-label value provider used by the token-resolution test.
  def coins(_scope), do: "1234"
  def boom(_scope), do: raise("nope")
end

defmodule GamendWeb.HostLayoutNavigationTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GamendWeb.HostLayoutNavigation

  defp base_assigns(primary_links) do
    %{
      current_scope: nil,
      current_path: "/",
      current_query: "",
      navigation: %{"primary_links" => primary_links},
      notif_unread_count: 0,
      locale: "en",
      known_locales: []
    }
  end

  test "per-item color class is applied to the icon" do
    html =
      render_component(
        &HostLayoutNavigation.desktop_nav/1,
        base_assigns([
          %{
            "label" => "Shop",
            "href" => "/shop",
            "icon" => "hero-star",
            "color" => "text-warning"
          }
        ])
      )

    assert html =~ "text-warning"
    assert html =~ "hero-star"
  end

  test "{Module.func} label tokens resolve via the named function" do
    html =
      render_component(
        &HostLayoutNavigation.desktop_nav/1,
        base_assigns([
          %{"label" => "{GamendWeb.NavTestProvider.coins}", "href" => "/shop"}
        ])
      )

    assert html =~ "1234"
    refute html =~ "{GamendWeb.NavTestProvider"
  end

  test "unknown or failing tokens render empty, never crash" do
    html =
      render_component(
        &HostLayoutNavigation.desktop_nav/1,
        base_assigns([
          %{"label" => "{Does.Not.Exist}", "href" => "/a"},
          %{"label" => "{GamendWeb.NavTestProvider.boom}", "href" => "/b"}
        ])
      )

    refute html =~ "Does.Not.Exist"
    refute html =~ "boom"
  end

  test "readonly items render as a non-link badge (no href, not clickable)" do
    html =
      render_component(
        &HostLayoutNavigation.desktop_nav/1,
        base_assigns([
          %{
            "label" => "{GamendWeb.NavTestProvider.coins}",
            "icon" => "hero-star",
            "color" => "text-warning",
            "readonly" => true
          }
        ])
      )

    assert html =~ "1234"
    assert html =~ "text-warning"
    # non-interactive markers only the readonly item emits
    assert html =~ "pointer-events-none"
    assert html =~ ~s(aria-disabled="true")
  end

  test "a disabled link keeps its button look, has no href and shows its badge" do
    link = %{
      "label" => "Play",
      "href" => "/play",
      "icon" => "hero-play-solid",
      "badge" => "Coming soon",
      "disabled" => true
    }

    for render <- [&HostLayoutNavigation.desktop_nav/1, &HostLayoutNavigation.mobile_nav/1] do
      html = render_component(render, base_assigns([link]))

      refute html =~ ~s(href="/play")
      assert html =~ ~s(aria-disabled="true")
      assert html =~ "btn"
      assert html =~ ~r/Play.*badge.*Coming soon/s
    end
  end

  test "a disabled link inside a dropdown has no href and shows its badge" do
    nav = [
      %{
        "label" => "Learn",
        "items" => [
          %{"label" => "Tests", "href" => "/tests"},
          %{"label" => "Play", "href" => "/play", "badge" => "Coming soon", "disabled" => true}
        ]
      }
    ]

    html = render_component(&HostLayoutNavigation.desktop_nav/1, base_assigns(nav))

    assert html =~ ~s(href="/tests")
    refute html =~ ~s(href="/play")
    assert html =~ "Coming soon"
  end

  test "a badge on a working link keeps the link" do
    html =
      render_component(
        &HostLayoutNavigation.desktop_nav/1,
        base_assigns([%{"label" => "Classes", "href" => "/classes", "badge" => "Pro"}])
      )

    assert html =~ ~s(href="/classes")
    assert html =~ ~r/Classes.*badge.*Pro/s
    refute html =~ "aria-disabled"
  end

  test "desktop dropdown highlights the active sub-item with daisyUI menu-active" do
    nav = [
      %{
        "label" => "Social",
        "items" => [
          %{"label" => "Leaderboards", "href" => "/leaderboards", "match" => "prefix"}
        ]
      }
    ]

    assigns = %{base_assigns(nav) | current_path: "/leaderboards"}
    html = render_component(&HostLayoutNavigation.desktop_nav/1, assigns)

    # daisyUI 5 styles the active menu item via .menu-active (not .active)
    assert html =~ "menu-active"
  end

  # `/docs` and `/docs/reference` both start the page's path; only the more
  # specific one is where the reader is.
  test "only the most specific sibling is active, on desktop and mobile" do
    nav = [
      %{
        "label" => "Docs",
        "items" => [
          %{"label" => "Documentation", "href" => "/docs"},
          %{"label" => "Reference", "href" => "/docs/reference"}
        ]
      }
    ]

    assigns = %{base_assigns(nav) | current_path: "/docs/reference/components/body2d"}

    desktop = render_component(&HostLayoutNavigation.desktop_nav/1, assigns)
    assert [_one] = Regex.scan(~r/menu-active/, desktop)
    assert desktop =~ ~r{href="/docs/reference"\s+class="menu-active"}

    mobile = render_component(&HostLayoutNavigation.mobile_nav/1, assigns)
    refute mobile =~ ~r{href="/docs"\s+class="btn w-full justify-start btn-primary"}
    assert mobile =~ ~r{href="/docs/reference"\s+class="btn w-full justify-start btn-primary"}

    # A page only the broad link matches still lights it.
    guide = %{assigns | current_path: "/docs/manual/scenes"}

    assert render_component(&HostLayoutNavigation.desktop_nav/1, guide) =~
             ~r{href="/docs"\s+class="menu-active"}
  end

  # `/games` starts with the letters of `/game`; they are different pages, in
  # different groups, so the sibling rule above cannot settle it.
  test "a prefix match stops at a path segment" do
    nav = [
      %{"label" => "Learn", "items" => [%{"label" => "Word games", "href" => "/games"}]},
      %{"label" => "News", "items" => [%{"label" => "The Game", "href" => "/game"}]}
    ]

    games = %{base_assigns(nav) | current_path: "/games"}
    html = render_component(&HostLayoutNavigation.desktop_nav/1, games)
    assert html =~ ~r{href="/games"\s+class="menu-active"}
    refute html =~ ~r{href="/game"\s+class="menu-active"}

    nested = %{games | current_path: "/game/web"}
    html = render_component(&HostLayoutNavigation.desktop_nav/1, nested)
    assert html =~ ~r{href="/game"\s+class="menu-active"}
    refute html =~ ~r{href="/games"\s+class="menu-active"}
  end

  test "mobile hamburger is a <details> toggle (native open/close, focus-independent)" do
    html =
      render_component(
        &HostLayoutNavigation.mobile_nav/1,
        base_assigns([
          %{"label" => "Play", "href" => "/play"}
        ])
      )

    # A <details data-navbar-dropdown> with a <summary> trigger — not a
    # tabindex/focus dropdown (which gets stuck when focus is lost on alt-tab).
    assert html =~ ~r/<details[^>]*data-navbar-dropdown/
    assert html =~ ~r/<summary[^>]*aria-label/
    refute html =~ ~s(<button\n)
    refute html =~ ~s(tabindex="0")
  end

  test "mobile: one top-level group open at a time, nested groups left alone" do
    html =
      render_component(
        &HostLayoutNavigation.mobile_nav/1,
        base_assigns([
          %{
            "label" => "Learn",
            "items" => [
              %{"label" => "Words", "href" => "/words"},
              %{"label" => "More", "items" => [%{"label" => "Tests", "href" => "/tests"}]}
            ]
          },
          %{"label" => "Social", "items" => [%{"label" => "Friends", "href" => "/friends"}]}
        ])
      )

    # A shared `<details name>` is the browser's own accordion. The nested
    # "More" must not share it, or opening it would close "Learn" around it.
    assert length(Regex.scan(~r/<details[^>]*name="mobile-nav"/, html)) == 2
    assert length(Regex.scan(~r/<details(?![^>]*data-navbar-dropdown)[^>]*>/, html)) == 3
  end

  test "mobile: pinned items render inline (outside the dropdown menu)" do
    html =
      render_component(
        &HostLayoutNavigation.mobile_nav/1,
        base_assigns([
          %{"label" => "Coins", "href" => "/shop", "icon" => "hero-star", "mobile" => "pinned"},
          %{"label" => "Play", "href" => "/play"}
        ])
      )

    # Pinned link is present, and it sits before the dropdown menu markup.
    assert html =~ ~s(href="/shop")
    [before_menu, _menu] = String.split(html, "dropdown-content", parts: 2)
    assert before_menu =~ ~s(href="/shop")
    refute before_menu =~ ~s(href="/play")
  end
end
