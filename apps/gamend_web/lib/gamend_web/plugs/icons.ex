defmodule GamendWeb.Plugs.Icons do
  @moduledoc """
  Serves the typed icon set as SVG, so an entity's `icon_url` can point at an
  icon we already ship instead of an image someone has to host.

      GET /icons/trophy.svg
      GET /icons/outline/trophy.svg   (also mini, micro: the `hero-*` classes)

  and every icon in one file, `GET /icons/sprite.svg?v=…`
  (`GamendWeb.Icons.sprite_path/0`), which a page that draws many of them at
  once (`<.icon_picker>`) points `<use>` at.

  The web UI draws them from here too, as a mask over `currentColor` so they
  follow the theme (`GamendWeb.Icons.draw_path/1`, the URL with its content
  hash); game clients, mobile and anything reading `icon_url` from the API
  fetch the same files.

  An endpoint plug, beside the static ones and ahead of `RealIp`, `GeoCountry`,
  `IpBan`, the rate limiter and the session, as a file under `priv/static`
  would be (2026-11-13). Routed, each icon was a request of the visitor's
  budget (240 a minute) and a geo stat: a page draws 30 to 60 of them and
  `/admin` about 40, so a few people behind one address (an office, a school)
  were refused with 429s. Not `Plug.Static` itself: the icons are the heroicons
  dependency's, embedded at compile time (`GamendWeb.Icons`), and the host
  declares that dependency, so there is no file under `priv/static` to serve.

  The web UI's URL carries the content hash, so it is cached for good and a
  new heroicons release is a new URL; a bare URL is cached for a day.
  """

  @behaviour Plug

  import Plug.Conn

  alias GamendWeb.Icons
  alias GamendWeb.Router.Shared, as: RouterShared

  @icons "icons"
  @sprite "sprite.svg"
  @methods ~w(GET HEAD)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, path_info: [@icons | rest]} = conn, _opts)
      when method in @methods do
    case lookup(rest) do
      {:ok, svg} ->
        conn |> send_svg(svg) |> halt()

      :error ->
        conn |> put_resp_content_type("text/plain") |> send_resp(404, "not found") |> halt()

      # Deeper than any icon: the router answers it, as any unknown path.
      :pass ->
        conn
    end
  end

  def call(conn, _opts), do: conn

  defp lookup([@sprite]), do: {:ok, Icons.sprite()}

  defp lookup([name]) do
    case Icons.from_path("/" <> @icons <> "/" <> name) do
      {:ok, icon} -> {:ok, Icons.svg(icon)}
      :error -> :error
    end
  end

  defp lookup([set, name]), do: Icons.set_file(set, name)
  defp lookup(_path), do: :pass

  # A URL with its content hash (`?v=`, every one the web UI draws) is that
  # revision for good; a bare one, as an `icon_url` stores it, is checked
  # again daily, so a new heroicons release reaches a client in a day.
  defp send_svg(conn, svg) do
    conn = fetch_query_params(conn)

    cache =
      if is_map_key(conn.query_params, "v"),
        do: "public, max-age=31536000, immutable",
        else: "public, max-age=86400"

    # The pages' policy, as the routed icons had: an SVG opened on its own is
    # a document.
    conn
    |> merge_resp_headers(RouterShared.browser_headers())
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", cache)
    |> send_resp(200, svg)
  end
end
