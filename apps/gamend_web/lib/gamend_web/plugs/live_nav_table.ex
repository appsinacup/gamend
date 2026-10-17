defmodule GamendWeb.Plugs.LiveNavTable do
  @moduledoc """
  Serves `GamendWeb.LiveNav`'s route table at `/gamend/live-nav.json`.

  In the endpoint, ahead of the router: it is not a page, needs no session,
  and every host gets it without a route of its own. Cached for a year when the
  request names the current version (`?v=`, which the root layout writes), and
  revalidated otherwise.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: "/gamend/live-nav.json"} = conn, _opts) do
    %{version: version, json: json} = GamendWeb.LiveNav.table()
    conn = fetch_query_params(conn)

    cache =
      if conn.query_params["v"] == version,
        do: "public, max-age=31536000, immutable",
        else: "no-cache"

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", cache)
    |> send_resp(200, json)
    |> halt()
  end

  def call(conn, _opts), do: conn
end
