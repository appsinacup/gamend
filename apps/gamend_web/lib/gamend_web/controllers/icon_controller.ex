defmodule GamendWeb.IconController do
  @moduledoc """
  Serves the typed icon set as SVG, so an entity's `icon_url` can point at an
  icon we already ship instead of an image someone has to host.

      GET /icons/trophy.svg

  and every icon in one file, `GET /icons/sprite.svg?v=…`
  (`GamendWeb.Icons.sprite_path/0`), which a page that draws many of them at
  once (`<.icon_picker>`) points `<use>` at.

  The web UI does not actually fetch these — it recognises its own URLs and
  inlines the SVG so `currentColor` follows the theme. This route is for
  everyone else: game clients, mobile, anything reading `icon_url` from the
  API.

  The body is a compile-time constant keyed by name, so it can be cached
  forever.
  """

  use GamendWeb, :controller

  alias GamendWeb.Icons

  def show(conn, %{"name" => "sprite.svg"}), do: send_svg(conn, Icons.sprite())

  def show(conn, %{"name" => name}) do
    case Icons.from_path("/icons/" <> name) do
      {:ok, icon} -> send_svg(conn, Icons.svg(icon))
      :error -> conn |> put_status(:not_found) |> text("not found")
    end
  end

  defp send_svg(conn, svg) do
    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> send_resp(200, svg)
  end
end
