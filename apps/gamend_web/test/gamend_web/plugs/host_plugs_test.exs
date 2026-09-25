defmodule GamendWeb.HostPlugsTest do
  # Not async: `:host_plugs` is application env, read by the endpoint on every
  # request, and another test's request must not meet this test's plug.
  use GamendWeb.ConnCase, async: false

  defmodule GamesHost do
    @behaviour Plug
    import Plug.Conn

    def init(opts), do: Keyword.put_new(opts, :host, "games.example.test")

    def call(%{host: host} = conn, opts) do
      if host == opts[:host] do
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, "game at #{conn.request_path}")
        |> halt()
      else
        conn
      end
    end
  end

  setup do
    previous = Application.get_env(:gamend_web, :host_plugs)
    Application.put_env(:gamend_web, :host_plugs, [GamesHost])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, :host_plugs, previous),
        else: Application.delete_env(:gamend_web, :host_plugs)
    end)
  end

  test "a host plug answers its own host before the trailing-slash redirect and the session", %{
    conn: conn
  } do
    conn = get(%{conn | host: "games.example.test"}, "/my-game/")

    assert conn.status == 200
    assert conn.resp_body == "game at /my-game/"
    assert get_resp_header(conn, "set-cookie") == []
    # Before SecurityHeaders too: the plug decides what its host is framed by.
    assert get_resp_header(conn, "x-frame-options") == []
  end

  test "every other host goes through the site as before", %{conn: conn} do
    conn = get(conn, "/blog/")

    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["/blog"]
  end

  test "a plug given as {module, opts} is initialised with them", %{conn: conn} do
    Application.put_env(:gamend_web, :host_plugs, [{GamesHost, host: "other.example.test"}])

    assert get(%{conn | host: "other.example.test"}, "/x").resp_body == "game at /x"
    assert get(%{conn | host: "games.example.test"}, "/blog/").status == 301
  end
end
