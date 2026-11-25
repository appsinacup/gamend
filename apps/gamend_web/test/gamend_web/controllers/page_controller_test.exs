defmodule GamendWeb.PageControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Content
  alias Gamend.Repo
  alias Gamend.Theme.JSONConfig

  setup do
    # Ensure a known GAMEND_CONTENT_THEME_CONFIG is active so tests aren't affected by other
    # modules that may delete/restore the env var concurrently.
    # Use a temp file with known content for reliable path resolution.
    orig =
      Gamend.SettingsHelpers.get(:gamend_core, Gamend.ContentSettings, :theme_config)

    base =
      Path.join(System.tmp_dir!(), "theme_page_test_#{System.unique_integer([:positive])}.json")

    theme = %{
      "title" => "Gamend",
      "tagline" => "Game + Backend",
      "contact_email" => "legal@example.com",
      "logo" => "/images/logo.png",
      "banner" => "/images/banner.png",
      "favicon" => "/favicon.ico",
      "pages" => %{
        "home" => %{
          "path" => "/",
          "hero" => %{
            "title" => "Gamend",
            "text" => "**Open source** backend for real-time games.",
            "image" => %{
              "light" => "/images/banner.png",
              "alt" => "Gamend"
            },
            "buttons" => [
              %{
                "label" => "Discord",
                "href" => "https://discord.com/invite/example",
                "icon" => "hero-chat-bubble-left-ellipsis-solid",
                "external" => true
              }
            ]
          },
          "sections_height" => "half",
          "sections" => [
            %{
              "title" => "Authentication & Users",
              "text" =>
                "Email, Magic-link, OAuth, JWT and Session. Register, login, reset password and verify email.",
              "icon" => "hero-lock-closed-solid"
            },
            %{
              "title" => "Server Scripting & Scheduling",
              "text" =>
                "Extend server logic with Elixir scripts. Schedule automated tasks and cron jobs.",
              "icon" => "hero-puzzle-piece-solid"
            }
          ]
        },
        "about" => %{
          "path" => "/about",
          "hero" => %{
            "title" => "About Gamend",
            "text" => "Reusable **presentation** page.",
            "image" => %{"light" => "/images/logo.png", "alt" => "Gamend"},
            "buttons" => [
              %{"label" => "Docs", "href" => "/docs/setup", "icon" => "hero-book-open-solid"}
            ]
          },
          "sections" => [
            %{
              "title" => "Built For Teams",
              "text" => "Fork, theme, host, and extend.",
              "image" => %{"light" => "/images/logo.png", "alt" => "Built For Teams"}
            }
          ]
        },
        "brand" => %{
          "path" => "/brand",
          "hero" => %{
            "title" => "Brand Page",
            "text" => "Configured from pages map.",
            "image" => %{"light" => "/images/logo.png", "alt" => "Brand Page"}
          },
          "sections" => []
        }
      },
      "footer" => %{
        "sections" => [
          %{
            "title" => "Privacy & Terms",
            "links" => [
              %{"label" => "Privacy Policy", "href" => "/privacy"},
              %{"label" => "Terms and Conditions", "href" => "/terms"}
            ]
          }
        ]
      },
      "navigation" => %{
        "primary_links" => [
          %{"label" => "Play", "href" => "/play", "icon" => "hero-play-solid"},
          %{
            "label" => "Social",
            "icon" => "hero-user-group-solid",
            "items" => [
              %{
                "label" => "Leaderboards",
                "href" => "/leaderboards",
                "icon" => "hero-chart-bar-solid"
              },
              %{
                "label" => "Achievements",
                "href" => "/quests",
                "icon" => "hero-trophy-solid"
              },
              %{"label" => "Groups", "href" => "/groups", "icon" => "hero-user-group-solid"},
              %{
                "label" => "Parties",
                "href" => "/parties",
                "icon" => "hero-user-plus-solid",
                "auth" => "authenticated"
              }
            ]
          }
        ],
        "account_links" => [
          %{"label" => "Billing", "href" => "/billing"},
          %{"label" => "Admin Console", "href" => "/admin", "admin_only" => true},
          %{"label" => "Admin Reports", "href" => "/admin/reports", "auth" => "admin"}
        ]
      }
    }

    File.write!(base, Jason.encode!(theme))

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.ContentSettings,
      :theme_config,
      base
    )

    JSONConfig.reload()
    Content.reload()

    on_exit(fn ->
      if orig,
        do:
          Gamend.SettingsHelpers.put(
            :gamend_core,
            Gamend.ContentSettings,
            :theme_config,
            orig
          ),
        else:
          Gamend.SettingsHelpers.delete(
            :gamend_core,
            Gamend.ContentSettings,
            :theme_config
          )

      JSONConfig.reload()
      Content.reload()
      File.rm(base)
    end)

    :ok
  end

  test "home shows configured presentation sections", %{conn: conn} do
    conn = get(conn, "/")
    body = html_response(conn, 200)

    assert body =~ "Gamend"
    assert body =~ "Discord"
    assert body =~ "Email, Magic-link, OAuth, JWT and Session."
    assert body =~ "Authentication &amp; Users"
    assert body =~ "Server Scripting &amp; Scheduling"
    assert body =~ "Privacy &amp; Terms"
    refute body =~ "Online"
  end

  test "configured pages render by path from pages map", %{conn: conn} do
    conn = get(conn, "/brand")
    body = html_response(conn, 200)

    assert body =~ "Brand Page"
    assert body =~ "Configured from pages map."
  end

  test "unconfigured page path returns the 404 page", %{conn: conn} do
    # This path decides for itself that the request is a 404, so it never
    # reaches `render_errors`, and still answers with the page, not nine bytes
    # of plain "Not Found", which reads as though the whole site is down.
    conn = get(conn, "/missing-page")
    body = html_response(conn, 404)

    assert body =~ "Page not found"
    assert body =~ ~s(href="/")
    refute body == "Not Found"
  end

  test "the default locale's prefix is a permanent redirect", %{conn: conn} do
    # 301, not 302: the default locale is never served under a prefix whatever
    # `:localized_paths` says, so a crawler should consolidate the two and stop
    # re-crawling. A 302 says "the prefixed URL is the real one, back soon",
    # which keeps it in the index — 229 URLs' worth of "Page with redirect".
    conn = get(conn, "/en/about")

    assert conn.status == 301
    assert redirected_to(conn, 301) == "/about"
  end

  test "a path not served under prefixes stays a temporary redirect", %{conn: conn} do
    # Whether this redirects is a `:localized_paths` config decision, so it must
    # not be cached as permanent by every browser that ever saw it.
    conn = get(conn, "/ro/some-unlocalized-page")

    assert conn.status == 302
  end

  test "the locale switcher never links the default locale under a prefix", %{conn: conn} do
    # `/en/` redirects to `/` — the default locale is never served prefixed. On
    # a localized path the switcher's `nofollow` does not apply, so a prefixed
    # default link is a followable link that can only ever redirect. Google
    # reported 229 of these as "Page with redirect".
    body = html_response(get(conn, "/"), 200)

    refute body =~ ~s(href="/en"),
           ~s(the switcher linked /en, which redirects to the clean URL)

    # It still has to offer English — pointing at the clean URL instead.
    assert body =~ ~s(href="/")
    # Other locales keep their prefix: those are real, separately indexable pages.
    assert body =~ ~s(href="/ro")
  end

  test "home renders in the visitor's locale", %{conn: conn} do
    # `/` is a localized path, so the prefixed URL is served directly rather
    # than redirected — that is what makes the Romanian home page indexable.
    conn = get(conn, "/ro")
    assert html_response(conn, 200) =~ ~s(lang="ro")

    # The unprefixed URL is the default-locale document, so a reader who has
    # chosen another language is *sent to that language's URL* rather than
    # served it here. Serving it here would make one URL as many documents as
    # there are locales: uncacheable, and with no stable canonical form for a
    # crawler. The reader still ends up in Romanian, at an address that says so.
    redirected = get(recycle(conn), "/")
    assert redirected_to(redirected) == "/ro"

    conn = get(recycle(conn), "/ro")
    body = html_response(conn, 200)

    assert body =~ ~s(lang="ro")
    # The locale switcher shows flags as files now, not `.fi-*` background classes.
    assert body =~ "/flags/ro.svg"

    # Chrome this app owns and translates itself. Labels that come from the
    # theme config are translated through the host's `theme` domain, which
    # this app's test env has no backend for.
    assert body =~ "Clasamente"
    assert body =~ "Grupuri"
    assert body =~ "Conectare"
  end

  test "home renders without errors when GAMEND_CONTENT_THEME_CONFIG is unset", %{conn: conn} do
    Gamend.SettingsHelpers.delete(
      :gamend_core,
      Gamend.ContentSettings,
      :theme_config
    )

    JSONConfig.reload()
    Content.reload()

    conn = get(conn, "/")
    # Page should render without crashing even with no theme configured
    assert html_response(conn, 200) =~ "<html"
  end

  test "home hides admin-only account links for non-admin users", %{conn: conn} do
    user =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => false})
      |> Repo.update!()

    body =
      conn
      |> log_in_user(user)
      |> get("/")
      |> html_response(200)

    assert body =~ "href=\"/billing\""
    refute body =~ "href=\"/admin\""
    refute body =~ "href=\"/admin/reports\""
  end

  test "home hides auth-only dropdown items from guests", %{conn: conn} do
    body =
      conn
      |> get("/")
      |> html_response(200)

    assert body =~ "href=\"/leaderboards\""
    refute body =~ "href=\"/parties\""
  end

  test "home shows auth-only dropdown items to signed-in users", %{conn: conn} do
    user =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => false})
      |> Repo.update!()

    body =
      conn
      |> log_in_user(user)
      |> get("/")
      |> html_response(200)

    assert body =~ "href=\"/leaderboards\""
    assert body =~ "href=\"/parties\""
  end

  test "home shows admin-only account links for admin users", %{conn: conn} do
    user =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update!()

    body =
      conn
      |> log_in_user(user)
      |> get("/")
      |> html_response(200)

    assert body =~ "href=\"/billing\""
    assert body =~ "href=\"/admin\""
    assert body =~ "href=\"/admin/reports\""
  end

  # The reference page: every example captioned with its classes, and kept out
  # of search, since it is a reference and not content.
  test "the UI page shows the building blocks and is not indexed", %{conn: conn} do
    body = conn |> get("/ui") |> html_response(200)

    assert body =~ "UI elements"
    assert body =~ ~s(<meta name="robots" content="noindex, follow")

    for class <- [
          "btn btn-primary",
          "btn btn-surface",
          "btn btn-ghost btn-circle",
          "badge badge-primary",
          "alert alert-info"
        ] do
      assert body =~ ~s(class="#{class}), "no #{class} specimen"
      assert body =~ "#{class}</figcaption>", "#{class} is not captioned"
    end

    for id <- ~w(buttons badges forms alerts surfaces colours type feedback) do
      assert body =~ ~s(id="#{id}"), "no #{id} section"
      assert body =~ ~s(href="##{id}"), "#{id} is not in the page's contents"
    end
  end

  test "legal pages give the theme's contact email as a mailto link", %{conn: conn} do
    for path <- ["/privacy", "/data_deletion", "/terms"] do
      body = conn |> get(path) |> html_response(200)

      assert body =~ ~s(href="mailto:legal@example.com"), path
      refute body =~ "support channels", path
    end
  end

  test "legal pages fall back to support channels without a contact email", %{conn: conn} do
    path =
      Path.join(System.tmp_dir!(), "theme_no_email_#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(%{"title" => "Gamend"}))
    on_exit(fn -> File.rm(path) end)

    Gamend.SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :theme_config, path)
    JSONConfig.reload()
    Content.reload()

    for path <- ["/privacy", "/data_deletion", "/terms"] do
      body = conn |> get(path) |> html_response(200)

      refute body =~ "mailto:", path
      assert body =~ "support", path
    end
  end

  test "the layout links the privacy and terms pages", %{conn: conn} do
    body = conn |> get("/") |> html_response(200)

    assert body =~ ~s(href="/privacy")
    assert body =~ ~s(href="/terms")
  end

  test "footer column labels are not headings", %{conn: conn} do
    body = conn |> get("/") |> html_response(200)

    # A footer column label names a group of links, not a section of this
    # document. As an `<h2>` it landed in the page outline beside the page's
    # real subject — and since the footer repeats on every page, that was most
    # of the H2s on the site. `<nav aria-label>` keeps the group announced to
    # screen readers, which is the part the heading was actually doing.
    assert body =~ ~s(aria-label="Privacy &amp; Terms")
    refute body =~ ~r{<h2[^>]*>\s*Privacy &amp; Terms\s*</h2>}

    # The label still renders; this is about which element carries it.
    assert body =~ "Privacy &amp; Terms"
  end
end
