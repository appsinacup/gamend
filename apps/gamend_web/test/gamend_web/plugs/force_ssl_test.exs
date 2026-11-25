defmodule GamendWeb.Plugs.ForceSSLTest do
  @moduledoc """
  `GAMEND_TLS_FORCE=true` is read at boot. Phoenix's `:force_ssl` endpoint
  option is read with `Application.compile_env/2` and so is decided when the
  endpoint is compiled, which would leave every page a live plain-HTTP twin
  for Search Console to index.

  These pin the redirect to the runtime setting, and pin the two paths that
  must survive it.
  """
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias GamendWeb.Plugs.ForceSSL

  setup do
    previous = Application.get_env(:gamend_web, GamendWeb.Tls, [])

    on_exit(fn -> Application.put_env(:gamend_web, GamendWeb.Tls, previous) end)

    %{opts: ForceSSL.init([]), previous: previous}
  end

  defp force(value, previous) do
    Application.put_env(:gamend_web, GamendWeb.Tls, Keyword.put(previous, :force, value))
  end

  defp http(path), do: %{conn(:get, "http://example.com" <> path) | scheme: :http}

  test "redirects plain HTTP to HTTPS when the setting is on", %{opts: opts, previous: previous} do
    force(true, previous)

    conn = ForceSSL.call(http("/pl"), opts)

    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["https://example.com/pl"]
    assert conn.halted
  end

  test "keeps the query string", %{opts: opts, previous: previous} do
    force(true, previous)

    conn = ForceSSL.call(%{http("/play") | query_string: "mode=coop"}, opts)

    assert get_resp_header(conn, "location") == ["https://example.com/play?mode=coop"]
  end

  test "does nothing when the setting is off", %{opts: opts, previous: previous} do
    force(false, previous)

    conn = ForceSSL.call(http("/pl"), opts)

    refute conn.halted
    assert conn.status == nil
  end

  test "leaves an HTTPS request alone", %{opts: opts, previous: previous} do
    force(true, previous)

    conn = ForceSSL.call(conn(:get, "https://example.com/pl"), opts)

    refute conn.halted
  end

  test "never redirects the ACME challenge — certbot fetches it over HTTP", %{
    opts: opts,
    previous: previous
  } do
    force(true, previous)

    conn = ForceSSL.call(http("/.well-known/acme-challenge/sometoken"), opts)

    refute conn.halted
  end

  test "never redirects the health endpoint or localhost", %{opts: opts, previous: previous} do
    force(true, previous)

    refute ForceSSL.call(http("/api/v1/health"), opts).halted
    refute ForceSSL.call(%{conn(:get, "http://localhost/pl") | scheme: :http}, opts).halted
  end

  test "leaves HSTS to SecurityHeaders rather than sending it twice", %{
    opts: opts,
    previous: previous
  } do
    force(true, previous)

    conn = ForceSSL.call(conn(:get, "https://example.com/pl"), opts)

    assert get_resp_header(conn, "strict-transport-security") == []
  end

  test "does not log a line per redirect", %{opts: opts, previous: previous} do
    force(true, previous)

    log = ExUnit.CaptureLog.capture_log(fn -> ForceSSL.call(http("/pl"), opts) end)

    refute log =~ "redirecting"
  end

  describe "wired into the endpoint" do
    test "a plain-HTTP request through the real pipeline redirects", %{previous: previous} do
      # The unit tests above would still pass with the plug sitting in a file
      # nothing plugs. This is the part that actually broke.
      force(true, previous)

      conn =
        GamendWeb.Endpoint.call(%{conn(:get, "http://example.com/") | scheme: :http}, [])

      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["https://example.com/"]
    end
  end
end
