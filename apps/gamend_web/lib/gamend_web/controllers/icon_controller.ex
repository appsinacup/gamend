defmodule GamendWeb.IconController do
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

  Not `Plug.Static`: the icons are the heroicons dependency's, embedded at
  compile time, not files under `priv/static`. The web UI's URL carries the
  content hash, so it is cached for good and a new heroicons release is a
  new URL; a bare URL is cached for a day.
  """

  use GamendWeb, :controller

  alias GamendWeb.Icons

  def show(conn, %{"set" => set, "name" => name}) do
    case Icons.set_file(set, name) do
      {:ok, svg} -> send_svg(conn, svg)
      :error -> conn |> put_status(:not_found) |> text("not found")
    end
  end

  def show(conn, %{"name" => "sprite.svg"}), do: send_svg(conn, Icons.sprite())

  def show(conn, %{"name" => name}) do
    case Icons.from_path("/icons/" <> name) do
      {:ok, icon} -> send_svg(conn, Icons.svg(icon))
      :error -> conn |> put_status(:not_found) |> text("not found")
    end
  end

  # A URL with its content hash (`?v=`, every one the web UI draws) is that
  # revision for good; a bare one, as an `icon_url` stores it, is checked
  # again daily, so a new heroicons release reaches a client in a day.
  defp send_svg(conn, svg) do
    cache =
      if is_map_key(conn.query_params, "v"),
        do: "public, max-age=31536000, immutable",
        else: "public, max-age=86400"

    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", cache)
    |> send_resp(200, svg)
  end
end
