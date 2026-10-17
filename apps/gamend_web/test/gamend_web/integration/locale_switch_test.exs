defmodule GamendWeb.LocaleSwitchTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  test "locale-prefixed navigation persists locale and renders translated host labels", %{
    conn: conn
  } do
    conn = get(conn, "/es/leaderboards")

    assert redirected_to(conn) == "/leaderboards"
    assert get_session(conn, :preferred_locale) == "es"

    {:ok, _view, html} = conn |> recycle() |> live("/leaderboards")

    assert html =~ "Clasificaciones"
    assert html =~ "Iniciar sesi"
  end

  test "region locale prefixes normalize back to the canonical locale", %{conn: conn} do
    conn = get(conn, "/pt-br/leaderboards")

    assert redirected_to(conn) == "/leaderboards"
    assert get_session(conn, :preferred_locale) == "pt_BR"
  end

  describe "localized content paths" do
    test "are served at the prefixed URL so each translation is indexable", %{conn: conn} do
      conn = get(conn, "/es/privacy")

      assert conn.status == 200
      assert conn.assigns.seo_path == "/privacy"
      assert conn.assigns.locale_prefix == "es"
      # The router only ever sees the clean path.
      assert conn.path_info == ["privacy"]
    end

    test "self-canonicalize and advertise every translation", %{conn: conn} do
      html = conn |> get("/es/privacy") |> html_response(200)

      assert html =~ ~s(<link rel="canonical" href="http://localhost:4002/es/privacy")
      assert html =~ ~s(hreflang="x-default" href="http://localhost:4002/privacy")
      assert html =~ ~s(hreflang="de" href="http://localhost:4002/de/privacy")
      # The default locale stays on the clean URL rather than /en/.
      assert html =~ ~s(hreflang="en" href="http://localhost:4002/privacy")
    end

    test "the default locale is never served under a prefix", %{conn: conn} do
      # 301, not 302: the rule holds whatever `:localized_paths` says, so a
      # crawler should consolidate the two URLs rather than keep the prefixed
      # one indexed and come back for it.
      assert conn |> get("/en/privacy") |> redirected_to(301) == "/privacy"
    end

    test "switching back to the default locale rewrites the session", %{conn: conn} do
      # Without the param the clean URL is bounced straight back to the
      # session's locale, so English is unreachable from any translated page.
      conn = conn |> get("/es/privacy") |> recycle()

      assert redirected_to(conn |> get("/privacy")) == "/es/privacy"

      switched = conn |> recycle() |> get("/privacy?setlang=en")

      assert redirected_to(switched, 301) == "/privacy"
      assert get_session(switched, :preferred_locale) == "en"
      assert switched |> recycle() |> get("/privacy") |> html_response(200)
    end

    test "a switch keeps the rest of the query string", %{conn: conn} do
      conn = get(conn, "/privacy?ref=nav&setlang=de")

      assert redirected_to(conn, 301) == "/de/privacy?ref=nav"
      assert get_session(conn, :preferred_locale) == "de"
    end

    test "a switch replaces the prefix already in the path", %{conn: conn} do
      assert conn |> get("/es/privacy?setlang=de") |> redirected_to(301) == "/de/privacy"
      assert conn |> get("/es/privacy?setlang=en") |> redirected_to(301) == "/privacy"
      assert conn |> get("/es?setlang=en") |> redirected_to(301) == "/"
      assert conn |> get("/?setlang=de") |> redirected_to(301) == "/de"
    end

    test "an unknown switch value is ignored rather than redirected", %{conn: conn} do
      assert conn |> get("/privacy?setlang=xx") |> html_response(200)
    end

    test "the switcher's default-locale link carries the switch param", %{conn: conn} do
      html = conn |> get("/es/privacy") |> html_response(200)

      assert html =~ ~s(href="/privacy?setlang=en" rel="nofollow")
      # Every other locale still links its own prefixed, followable URL.
      assert html =~ ~s(href="/de/privacy")
      refute html =~ ~s(setlang=de)
    end

    test "a language switch is a page load, never a move over the socket", %{conn: conn} do
      # `live_nav.js` moves a plain link to a LiveView page over the open
      # socket, where `LocalePath` never runs: `/x?setlang=en` from an
      # unprefixed page in another language would mount in that language.
      html = conn |> get("/es/privacy") |> html_response(200)
      links = Regex.scan(~r/<a\b[^>]*setlang=[^>]*>|<a\b[^>]*href="\/de\/privacy"[^>]*>/, html)

      assert length(links) >= 2
      assert Enum.all?(links, fn [a] -> a =~ "data-no-live-nav" end)
    end

    test "unprefixed pages canonicalize to themselves without alternates", %{conn: conn} do
      html = conn |> get("/leaderboards") |> html_response(200)

      assert html =~ ~s(<link rel="canonical" href="http://localhost:4002/leaderboards")
      refute html =~ ~s(hreflang="de" href="http://localhost:4002/de/leaderboards")
    end
  end
end
