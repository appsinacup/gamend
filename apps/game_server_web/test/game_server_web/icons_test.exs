defmodule GameServerWeb.IconsTest do
  @moduledoc """
  `icon_url` holds one kind of thing — a URL — whether it points at an upload
  or at an icon the server ships. The web UI has to tell the two apart: a
  heroicon's `fill="currentColor"` resolves to black inside an `<img>`, so it
  would vanish against the dark theme. Ours are inlined instead.
  """

  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GameServerWeb.CoreComponents
  alias GameServerWeb.Icons

  defp render_icon(assigns) do
    render_component(&CoreComponents.entity_icon/1, Map.put_new(assigns, :class, "w-6 h-6"))
  end

  describe "path/1 and from_path/1" do
    test "round-trip every icon we ship" do
      for icon <- Icons.list() do
        assert {:ok, ^icon} = icon |> Icons.path() |> Icons.from_path()
      end
    end

    test "anything that is not one of ours is not claimed" do
      for url <- [
            "/images/logo.png",
            "https://cdn.example.com/icons/trophy.svg",
            "/icons/not-a-real-icon.svg",
            "/icons/trophy.png",
            "/icons/../../secret.svg",
            ""
          ] do
        assert Icons.from_path(url) == :error, "#{url} should not resolve"
      end
    end

    test "an unknown name cannot leak new atoms into the VM" do
      before = :erlang.system_info(:atom_count)

      assert Icons.from_path("/icons/definitely_not_an_atom_#{System.unique_integer()}.svg") ==
               :error

      assert :erlang.system_info(:atom_count) == before
    end
  end

  describe "entity_icon/1" do
    test "inlines one of ours, so currentColor follows the theme" do
      html = render_icon(%{icon_url: Icons.path(:trophy), type: :quest})

      assert html =~ "<svg"
      assert html =~ "currentColor"
      refute html =~ "<img", "our own icons must not go through <img>"
    end

    test "an uploaded image still renders as an img" do
      html = render_icon(%{icon_url: "/images/logo.png", type: :group})

      assert html =~ ~s(<img)
      assert html =~ ~s(src="/images/logo.png")
    end

    test "no icon at all falls back to the type default" do
      html = render_icon(%{type: :leaderboard})

      assert html =~ "<svg"

      assert html ==
               render_icon(%{
                 icon_url: Icons.path(Icons.default(:leaderboard)),
                 type: :leaderboard
               })
    end
  end

  describe "GET /icons/:name" do
    test "serves the SVG for clients that cannot inline it", %{conn: conn} do
      conn = get(conn, "/icons/trophy.svg")

      assert response_content_type(conn, :svg) =~ "image/svg+xml"
      assert response(conn, 200) =~ "<svg"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "a dasherized name resolves", %{conn: conn} do
      assert response(get(conn, "/icons/chart-bar.svg"), 200) =~ "<svg"
    end

    test "an unknown icon is a 404, not a crash", %{conn: conn} do
      assert response(get(conn, "/icons/nope.svg"), 404)
      assert response(get(conn, "/icons/trophy.png"), 404)
    end
  end
end
