defmodule GamendWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :gamend_web

  alias Phoenix.Socket.Transport
  alias Phoenix.Transports.WebSocket

  @session_options [
    store: :cookie,
    key: "_gamend_key",
    signing_salt: "G8u1px36",
    same_site: "Lax",
    secure: Application.compile_env(:gamend_web, :session_secure, false)
  ]

  # The game socket. Its idle timeout and frame cap are settings
  # (`GamendWeb.Realtime`), but `socket/3` fixes a transport's options when the
  # endpoint compiles. So it is declared with no transport, which keeps Phoenix
  # supervising it, and `game_socket/2` below serves `/socket/websocket` with
  # options built at runtime.
  socket "/socket", GamendWeb.UserSocket, websocket: false, longpoll: false

  # `:user_agent` alongside the peer data: a page that adapts to the
  # visitor's platform — a download page highlighting their OS — reads it in
  # `mount/3` from the dead render and again on connect, and without it the
  # connected mount got `nil` and the highlight dropped a moment after it
  # appeared.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [:peer_data, :user_agent, session: @session_options],
      log: false,
      compress: true
    ],
    longpoll: [connect_info: [:user_agent, session: @session_options], log: false]

  # First, where Phoenix's own socket dispatch runs.
  plug :game_socket
  plug GamendWeb.Plugs.AcmeChallenge
  # After AcmeChallenge so certbot's HTTP-01 fetch is answered before any
  # redirect can touch it; before everything else so a plain-HTTP request
  # costs one 301 and nothing more.
  plug GamendWeb.Plugs.ForceSSL
  # A host app's own plugs, ahead of everything that assumes the request is
  # for this site: a second host name the app answers must not be sent to the
  # canonical host, given a session, or have its trailing slash taken away.
  plug :host_plugs
  # After ForceSSL so a plain-HTTP request to an alias costs one redirect to
  # https on the canonical host rather than two hops.
  plug GamendWeb.Plugs.CanonicalHost
  plug GamendWeb.Plugs.IndexNowKey
  plug GamendWeb.Plugs.SecurityHeaders
  plug GamendWeb.Plugs.WellKnown
  plug GamendWeb.Plugs.GameHeaders
  plug :serve_game_static
  plug :serve_host_static
  plug :serve_asset_static
  plug :serve_bundled_static
  plug GamendWeb.HostContentStatic

  # Two separate guards, deliberately. `Phoenix.CodeReloader` ships with
  # :phoenix, but `Phoenix.LiveReloader` is a `only: :dev` dependency — and
  # Mix never loads `only:` deps OF a dependency. So when a host app compiles
  # this app as a dep, `ensure_loaded?(Phoenix.LiveReloader)` is false, and a
  # single combined guard silently dropped code reloading too: every change,
  # host or plugin, needed a full server restart to take effect.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :gamend_web
  end

  # Browser auto-refresh is the part that genuinely needs the dev dependency.
  if code_reloading? and Code.ensure_loaded?(Phoenix.LiveReloader) and
       Code.ensure_loaded?(Phoenix.LiveReloader.Socket) do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  # Straight after RequestId, so everything logged for this request —
  # including the rate limiter's rejections and the router's own errors —
  # carries the client's session id and lands next to that client's own
  # uploaded lines.
  plug GamendWeb.Plugs.ClientSession
  plug GamendWeb.Plugs.RealIp
  plug GamendWeb.Plugs.GeoCountry
  plug GamendWeb.Plugs.IpBan
  plug GamendWeb.Plugs.RequestTimer

  plug Plug.Telemetry,
    event_prefix: [:phoenix, :endpoint],
    log: {__MODULE__, :access_log_level, []}

  # Test-only: every documented API response is checked against its schema.
  if Application.compile_env(:gamend_web, :response_contract, false) do
    plug GamendWeb.ResponseContract
  end

  # Before the body is parsed: a request over its limit is refused without
  # reading up to a megabyte of JSON or multipart first. CORS first, so a 429
  # still carries the headers a browser needs to let a web client read it.
  plug GamendWeb.Plugs.DynamicCors
  plug GamendWeb.Plugs.RateLimiter

  plug :parse_body

  plug Plug.MethodOverride
  plug Plug.Head

  # What Phoenix generates for a `socket/3` websocket transport: the same
  # config, loaded the same way, handed to the same plug. Built once per pair of
  # values, as `socket/3` builds it once per compile.
  defp game_socket(%Plug.Conn{path_info: ["socket", "websocket"]} = conn, _opts) do
    conn
    |> WebSocket.call({__MODULE__, GamendWeb.UserSocket, game_socket_opts()})
    |> halt()
  end

  defp game_socket(conn, _opts), do: conn

  defp game_socket_opts do
    timeout = max(Gamend.Settings.get(GamendWeb.Realtime, :socket_timeout_ms), 1_000)
    max_frame = max(Gamend.Settings.get(GamendWeb.Realtime, :socket_max_frame_bytes), 1_024)
    key = {__MODULE__, :game_socket, timeout, max_frame}

    case :persistent_term.get(key, nil) do
      nil ->
        opts =
          Transport.load_config(
            [log: false, compress: true, max_frame_size: max_frame, timeout: timeout],
            WebSocket
          )

        :persistent_term.put(key, opts)
        opts

      opts ->
        opts
    end
  end

  @parsers_opts [
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {GamendWeb.Plugs.RawBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()
  ]

  # The body limit is a setting (`GAMEND_HTTP_MAX_BODY_BYTES`), which a plug
  # declared with `plug Plug.Parsers, length: ...` would fix at compile time.
  # The parsers are built at runtime instead, once per limit.
  defp parse_body(conn, _opts), do: Plug.Parsers.call(conn, parsers_opts())

  defp parsers_opts do
    length = GamendWeb.Http.max_body_bytes()
    key = {__MODULE__, :parsers, length}

    case :persistent_term.get(key, nil) do
      nil ->
        opts = Plug.Parsers.init(Keyword.put(@parsers_opts, :length, length))
        :persistent_term.put(key, opts)
        opts

      opts ->
        opts
    end
  end

  @compiled_session_opts Plug.Session.init(@session_options)
  plug :maybe_session

  defp maybe_session(%{path_info: ["api", "v1" | _]} = conn, _opts), do: conn
  defp maybe_session(conn, _opts), do: Plug.Session.call(conn, @compiled_session_opts)

  plug GamendWeb.Plugs.LocalePath
  # After the static plugs — a file that exists is served as asked for — and
  # before the router, so `/docs/intro/` becomes `/docs/intro` for every
  # route rather than each page checking its own spelling.
  plug GamendWeb.Plugs.TrailingSlash
  plug :dispatch_router

  @access_log_pt_key {__MODULE__, :access_log_level}

  def access_log_level(_conn) do
    case :persistent_term.get(@access_log_pt_key, :not_set) do
      :not_set ->
        level =
          case Application.get_env(:gamend_web, __MODULE__)[:access_log] do
            level when level in [:debug, :info, :warning, :error] -> level
            false -> false
            _ -> :debug
          end

        :persistent_term.put(@access_log_pt_key, level)
        level

      cached ->
        cached
    end
  end

  # Files third parties fetch at a bare, un-fingerprinted path. They must stay
  # changeable: `robots.txt` under a year-long `immutable` meant a crawl-rule
  # change could not reach a client that had cached it, and `.well-known`
  # carries app-association files with the same problem. `llms.txt` is fetched
  # the same way and describes the site's current shape, so it belongs here too.
  @revalidating_static ~w(robots.txt llms.txt .well-known)

  defp serve_host_static(conn, _opts) do
    paths = host_static_paths() -- ~w(game)

    Plug.Static.call(
      conn,
      configurable_static_opts(
        :host_static_opts,
        host_static_app(),
        paths -- @revalidating_static
      )
    )
    |> case do
      %{halted: true} = halted ->
        halted

      passed ->
        Plug.Static.call(
          passed,
          configurable_static_opts(
            :revalidating_static_opts,
            host_static_app(),
            paths -- (paths -- @revalidating_static)
          )
        )
    end
  end

  defp serve_game_static(conn, _opts) do
    Plug.Static.call(
      conn,
      configurable_static_opts(:game_static_opts, host_static_app(), ~w(game))
    )
  end

  defp serve_asset_static(conn, _opts) do
    Plug.Static.call(
      conn,
      configurable_static_opts(:asset_static_opts, asset_static_app(), ~w(assets))
    )
  end

  # Bundled reference assets: shipped with the web app, requested without a
  # digest, and cached for a year by the `static_cache_control/1` catch-all.
  defp serve_bundled_static(conn, _opts) do
    Plug.Static.call(
      conn,
      configurable_static_opts(:bundled_static_opts, :gamend_web, ~w(fonts flags))
    )
  end

  # `config :gamend_web, :host_plugs, [MyApp.GamesHost, {MyApp.Other, opts}]`.
  # Each is `init/1`ed once per configuration and cached; the first to halt
  # ends the request, as any plug in this pipeline would.
  defp host_plugs(conn, _opts) do
    Enum.reduce_while(compiled_host_plugs(), conn, fn {plug, opts}, conn ->
      conn = plug.call(conn, opts)
      if conn.halted, do: {:halt, conn}, else: {:cont, conn}
    end)
  end

  defp compiled_host_plugs do
    configured = Application.get_env(:gamend_web, :host_plugs, [])

    case :persistent_term.get({__MODULE__, :host_plugs}, nil) do
      {^configured, compiled} ->
        compiled

      _ ->
        compiled =
          Enum.map(configured, fn
            {plug, opts} -> {plug, plug.init(opts)}
            plug -> {plug, plug.init([])}
          end)

        :persistent_term.put({__MODULE__, :host_plugs}, {configured, compiled})
        compiled
    end
  end

  defp dispatch_router(conn, _opts) do
    router = Application.get_env(:gamend_web, :router, GamendWeb.Router)
    router.call(conn, router.init([]))
  end

  defp configurable_static_opts(kind, from, only) do
    key = {__MODULE__, kind, from, only, gzip_static?(), brotli_static?()}

    case :persistent_term.get(key, :not_set) do
      :not_set ->
        opts =
          Plug.Static.init(
            at: "/",
            from: from,
            brotli: brotli_static?(),
            gzip: gzip_static?(),
            only: only,
            cache_control_for_etags: static_cache_control(kind),
            cache_control_for_vsn_requests: static_vsn_cache_control(kind),
            headers: static_headers(kind)
          )

        :persistent_term.put(key, opts)
        opts

      opts ->
        opts
    end
  end

  # Extra response headers per static kind. The game build needs
  # cross-origin isolation (COOP/COEP) when exported with thread support —
  # SharedArrayBuffer is gated on it — so hosts opt in via config, e.g.
  # config :gamend_web, :game_static_headers, %{"cross-origin-opener-policy" => ...}.
  defp static_headers(:game_static_opts) do
    Application.get_env(:gamend_web, :game_static_headers, %{})
  end

  defp static_headers(_kind), do: %{}

  defp static_cache_control(:revalidating_static_opts) do
    Application.get_env(
      :gamend_web,
      :revalidating_static_cache_control,
      "public, max-age=0, must-revalidate"
    )
  end

  defp static_cache_control(:game_static_opts) do
    Application.get_env(
      :gamend_web,
      :game_static_cache_control,
      "public, max-age=0, must-revalidate"
    )
  end

  defp static_cache_control(_kind) do
    Application.get_env(
      :gamend_web,
      :static_cache_control,
      "public, max-age=31536000, immutable"
    )
  end

  # A `?vsn=` request names one exact revision of a file, so it can be cached
  # forever whatever the plain URL's policy is — that is the whole point of the
  # parameter, and Plug.Static's own default.
  #
  # The revalidating kinds exist because Godot's export reuses filenames across
  # builds (`index.png`, `index.wasm`, `index.pck`), so a bare URL must be
  # rechecked or a deploy strands players on the previous build. Pinning vsn
  # requests to that same policy removed the only escape hatch: every asset paid
  # a round-trip on every load — measured at ~286 ms for a 304 carrying no
  # bytes — with no way for a caller to say "I want exactly this revision".
  defp static_vsn_cache_control(kind) do
    Application.get_env(
      :gamend_web,
      :"#{kind}_vsn_cache_control",
      Application.get_env(
        :gamend_web,
        :static_vsn_cache_control,
        "public, max-age=31536000, immutable"
      )
    )
  end

  defp host_static_app do
    Application.get_env(:gamend_web, :host_static_app, :gamend_web)
  end

  defp asset_static_app do
    Application.get_env(:gamend_web, :asset_static_app, host_static_app())
  end

  defp host_static_paths do
    Application.get_env(
      :gamend_web,
      :host_static_paths,
      ~w(images game favicon.ico robots.txt .well-known theme.css)
    )
  end

  defp gzip_static? do
    Application.get_env(:gamend_web, :gzip_static, false)
  end

  defp brotli_static? do
    Application.get_env(:gamend_web, :brotli_static, false)
  end
end
