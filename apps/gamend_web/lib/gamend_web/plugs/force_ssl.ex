defmodule GamendWeb.Plugs.ForceSSL do
  @moduledoc """
  Redirects plain HTTP to HTTPS when `GamendWeb.Tls`'s `:force` is on.

  A host on this stack binds port 80 itself, so without a redirect every page
  has a live plain-HTTP twin that a crawler will index — Search Console then
  reports `http://` URLs alongside the real ones.

  ## Why this is a plug and not endpoint config

  Phoenix's `:force_ssl` endpoint option cannot express a runtime setting:
  `Phoenix.Endpoint` reads it with `Application.compile_env/2` and decides
  **at compile time** whether to insert `Plug.SSL` into the endpoint. Setting
  it from `runtime.exs` — which is where every other setting on this stack
  comes from — writes a key nothing ever reads again, so the redirect silently
  never happens no matter what `GAMEND_TLS_FORCE` says.

  `Plug.SSL` itself still does the work; only the decision to call it is ours.

  HSTS is left to `GamendWeb.Plugs.SecurityHeaders`, which already sends it on
  every HTTPS response — `hsts: false` here just avoids a duplicate header.

  Plugged straight after `GamendWeb.Plugs.AcmeChallenge` so a Let's Encrypt
  HTTP-01 renewal is answered before this can redirect it, rather than relying
  only on the path exclusion below.
  """

  require Gamend.LocalHost, as: LocalHost

  @behaviour Plug

  @impl true
  def init(opts) do
    Plug.SSL.init(
      [
        rewrite_on: [:x_forwarded_proto, :x_forwarded_port],
        hsts: false,
        # Plug.SSL logs every redirect at :info. On a listener bots reach that
        # is a line per plain-HTTP hit, saying only that the thing we turned on
        # is on.
        log: false,
        exclude: [
          hosts: [LocalHost.localhost(), "127.0.0.1"],
          conn: {__MODULE__, :excluded?, []}
        ]
      ] ++ opts
    )
  end

  @impl true
  def call(conn, opts) do
    if Gamend.Settings.get(GamendWeb.Tls, :force) do
      Plug.SSL.call(conn, opts)
    else
      conn
    end
  end

  @doc """
  Paths that must stay reachable over plain HTTP.

  The ACME challenge because Let's Encrypt fetches it over HTTP by definition,
  and the health endpoint because a checker on the same box has no reason to
  carry a certificate.
  """
  @spec excluded?(Plug.Conn.t()) :: boolean()
  def excluded?(%Plug.Conn{} = conn) do
    String.starts_with?(conn.request_path, "/.well-known/acme-challenge") or
      conn.request_path == "/api/v1/health"
  end
end
