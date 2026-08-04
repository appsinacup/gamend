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
      assert conn |> get("/en/privacy") |> redirected_to() == "/privacy"
    end

    test "unprefixed pages canonicalize to themselves without alternates", %{conn: conn} do
      html = conn |> get("/leaderboards") |> html_response(200)

      assert html =~ ~s(<link rel="canonical" href="http://localhost:4002/leaderboards")
      refute html =~ ~s(hreflang="de" href="http://localhost:4002/de/leaderboards")
    end
  end
end
