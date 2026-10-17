defmodule GamendWeb.HostLayoutsTest do
  use ExUnit.Case, async: true

  alias GamendWeb.HostLayouts

  test "locale labels use display casing for native language names" do
    labels = HostLayouts.locale_labels()

    assert labels["cs"] == "Čeština"
    assert labels["fi"] == "Suomi"
    assert labels["hu"] == "Magyar"
  end

  test "theme image settings override host defaults" do
    theme =
      HostLayouts.resolve_theme("en", %{
        "title" => "Custom",
        "logo" => "/images/custom-logo.webp",
        "banner" => "/images/custom-banner.webp",
        "favicon" => "/images/custom.ico"
      })

    assert theme["logo"] == "/images/custom-logo.webp"
    assert theme["banner"] == "/images/custom-banner.webp"
    assert theme["favicon"] == "/images/custom.ico"
  end

  describe "navbar logo" do
    import Phoenix.LiveViewTest

    defp shell(theme) do
      render_component(&GamendWeb.HostLayoutShell.app/1, %{
        flash: %{},
        theme: Map.merge(%{"title" => "T"}, theme),
        locale: "en",
        inner_block: []
      })
    end

    # The `<img>` tags in the brand link, in order. The theme toggle further
    # down the bar uses the same `[[data-theme=dark]_&]` variant, so the
    # assertions read the tags rather than the page.
    defp logo_tags(html) do
      ~r/<img [^>]*>/
      |> Regex.scan(html)
      |> List.flatten()
      |> Enum.filter(&(&1 =~ "logo"))
    end

    test "one logo serves both themes when no dark one is named" do
      [light] = logo_tags(shell(%{"logo" => "/images/logo.png"}))

      assert light =~ ~s(src="/images/logo.png")
      refute light =~ "data-theme"
    end

    test "logo_dark is swapped in by the theme attribute" do
      [light, dark] =
        logo_tags(shell(%{"logo" => "/images/logo.png", "logo_dark" => "/images/logo-dark.png"}))

      assert light =~ ~s(src="/images/logo.png")
      # A dynamic class attribute escapes the `&`; the browser reads it back.
      assert light =~ ~r/\[\[data-theme=dark\]_&(amp;)?\]:hidden/
      assert dark =~ ~s(src="/images/logo-dark.png")
      assert dark =~ "hidden [[data-theme=dark]_&]:block"
    end
  end

  ## The shell derives ten assigns from five attrs, and a function component is
  ## stateless, so `assign/3` marks every one of them changed on every render
  ## unless something stops it. Left unstopped, the navbar and the footer
  ## re-render on every diff any LiveView sends, and the client morphs the
  ## server's markup back over the DOM — which closes an open `<details>`
  ## dropdown. Nothing about that is visible in rendered markup, so these
  ## assert on `__changed__` itself.
  describe "app shell change tracking" do
    @derived [
      :background_icons,
      :breadcrumbs,
      :current_path,
      :current_query,
      :footer,
      :known_locales,
      :locale,
      :navigation,
      :notif_unread_count,
      :theme
    ]

    defp app_assigns(changed) do
      %{
        __changed__: changed,
        flash: %{},
        current_scope: nil,
        current_path: "/tests/spanish",
        flush: false,
        background_icons: nil,
        inner_block: []
      }
    end

    test "a diff that only touched the page body leaves the shell alone" do
      changed = HostLayouts.prepare_app_assigns(app_assigns(%{inner_block: true})).__changed__

      assert Map.has_key?(changed, :inner_block)

      for key <- @derived do
        refute Map.has_key?(changed, key), "#{key} would re-render the navbar on every diff"
      end
    end

    test "a flash does not re-render the shell either" do
      changed = HostLayouts.prepare_app_assigns(app_assigns(%{flash: true})).__changed__

      for key <- @derived, do: refute(Map.has_key?(changed, key))
    end

    test "a new path re-renders the shell" do
      changed =
        HostLayouts.prepare_app_assigns(app_assigns(%{current_path: true})).__changed__

      for key <- @derived, do: assert(Map.has_key?(changed, key))
    end

    test "a change of scope re-renders the shell" do
      changed =
        HostLayouts.prepare_app_assigns(app_assigns(%{current_scope: true})).__changed__

      assert Map.has_key?(changed, :navigation)
      assert Map.has_key?(changed, :footer)
      assert Map.has_key?(changed, :notif_unread_count)
    end

    ## A nav label can read something the page changes (the coin badge after a
    ## purchase): `nav_key` is how the page says it moved.
    test "a new nav key re-renders the shell" do
      changed = HostLayouts.prepare_app_assigns(app_assigns(%{nav_key: true})).__changed__

      assert Map.has_key?(changed, :navigation)
    end

    ## `nil` is how the engine says "not change tracking" — a dead render, or a
    ## first render. Freezing anything there would leave the navbar unrendered.
    test "a render with no change tracking renders everything" do
      assigns = HostLayouts.prepare_app_assigns(app_assigns(nil))

      assert assigns.__changed__ == nil
      assert assigns.navigation
      assert assigns.theme["title"]
    end
  end
end
