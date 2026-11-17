defmodule GamendWeb.Plugs.RateLimiter do
  @moduledoc """
  Plug that rate-limits incoming HTTP requests per client IP.

  Uses `GamendWeb.RateLimit` (Hammer ETS backend) to enforce
  configurable limits per time window. Different path prefixes can have
  different limits (e.g. auth endpoints are stricter).

  ## Configuration

      config :gamend_web, GamendWeb.Plugs.RateLimiter,
        general_limit: 1200,         # requests per window
        general_window: 60_000,     # 60 seconds
        auth_limit: 30,             # login/registration
        auth_window: 60_000

  Responds with `429 Too Many Requests` when the limit is exceeded.
  """

  import Plug.Conn

  alias GamendWeb.Plugs.GeoCountry
  alias GamendWeb.Plugs.LocalePath

  # Declared so the values are documented, env-fed and visible in the admin
  # viewer; the `Keyword.get(config(), key, @default)` reads below are
  # unchanged, because a setting resolves into the app-env key they already
  # look at. Defaults are the production ones — `config/dev.exs` raises them
  # explicitly so local iteration is not throttled.
  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :ratelimit,
    label: "Rate limiting"

  require GamendWeb.ApiSegment, as: ApiSegment
  require GamendWeb.Plugs.RateLimitBucket, as: RateLimitBucket

  @log_in_actions ~w(log_in log-in)
  @browser_auth_actions ["register" | @log_in_actions]
  # Not `refresh`: a refresh token is a signed secret nobody can guess, so
  # counting it as a sign-in only throttled apps behind one address (a
  # classroom, a carrier) that reopen at once. It is in the general bucket.
  @auth_paths ~w(login register)
  @password_login "login"
  @post "POST"

  # Where `do_rate_limit/1` notes the auth bucket a password sign-in was
  # charged to, for `refund_login/1`.
  @login_charge :gamend_rate_limit_login_charge

  setting(:enabled, :boolean,
    default: true,
    doc: "Master switch for all request/message throttling."
  )

  setting(:general_limit, :integer,
    default: 240,
    doc: "Max general HTTP requests per window, per IP."
  )

  setting(:exempt_ips, :string,
    default: "",
    doc:
      "Client addresses never throttled, comma-separated, exact (IPv4 or IPv6), as `RealIp` resolves them: a load test from a known machine, a monitor. Empty: nobody."
  )

  setting(:general_window_ms, :integer,
    default: 60_000,
    doc: "General HTTP window, in milliseconds."
  )

  setting(:auth_limit, :integer,
    default: 10,
    doc:
      "Max sign-in and sign-up requests per window, per IP. A sign-in with the right " <>
        "password gives its request back, so only wrong passwords, device logins, " <>
        "sign-ups and OAuth use it up."
  )

  setting(:auth_window_ms, :integer,
    default: 60_000,
    doc: "Auth HTTP window, in milliseconds."
  )

  setting(:client_logs_limit, :integer,
    default: 30,
    doc: "Max client log batch uploads per window, per IP."
  )

  setting(:client_logs_window_ms, :integer,
    default: 60_000,
    doc: "Client log upload window, in milliseconds."
  )

  setting(:ws_limit, :integer,
    default: 60,
    doc: "Max WebSocket channel messages per window, per user."
  )

  setting(:ws_window_ms, :integer,
    default: 10_000,
    doc: "WebSocket window, in milliseconds."
  )

  setting(:dc_limit, :integer,
    default: 300,
    doc: "Max WebRTC DataChannel messages per window, per user."
  )

  setting(:dc_window_ms, :integer,
    default: 10_000,
    doc: "WebRTC DataChannel window, in milliseconds."
  )

  # Separate from the WS budget so ICE flooding cannot starve other events.
  setting(:ice_limit, :integer,
    default: 150,
    doc: "Max ICE candidate messages per window, per user."
  )

  setting(:ice_window_ms, :integer,
    default: 30_000,
    doc: "ICE candidate window, in milliseconds."
  )

  # The peer-to-peer signaling channel has budgets of its own: relaying SDP and
  # ICE between players is chattier than the user channel's traffic.
  setting(:signaling_ws_limit, :integer,
    default: 300,
    doc: "Max signaling channel messages per window, per user."
  )

  setting(:signaling_ws_window_ms, :integer,
    default: 10_000,
    doc: "Signaling channel window, in milliseconds."
  )

  setting(:signaling_ice_limit, :integer,
    default: 150,
    doc: "Max ICE candidates relayed over the signaling channel per window, per user."
  )

  setting(:signaling_ice_window_ms, :integer,
    default: 30_000,
    doc: "Signaling ICE window, in milliseconds."
  )

  def init(opts), do: opts

  def call(conn, _opts) do
    if enabled?() and not skip_path?(conn) and not exempt_ip?(conn) do
      do_rate_limit(conn)
    else
      conn
    end
  end

  # The addresses `exempt_ips` names. Split per request: the setting is empty
  # or a few addresses, and the split costs less than a bucket lookup.
  defp exempt_ip?(%{remote_ip: ip}) when is_tuple(ip) do
    case setting(:exempt_ips) do
      list when is_binary(list) and list != "" ->
        address = ip |> :inet.ntoa() |> to_string()
        address in (list |> String.split(",") |> Enum.map(&String.trim/1))

      _ ->
        false
    end
  end

  defp exempt_ip?(_conn), do: false

  # This plug runs before `LocalePath` (so before the body is parsed), and so
  # sees `/ro/users/log_in` where the router will see `/users/log_in`: strip the
  # locale here, or a localized login would count against the general bucket.
  defp routed_path([ApiSegment.api() | _] = path_info), do: path_info
  defp routed_path(path_info), do: LocalePath.strip_locale(path_info)

  # Skip rate limiting for internal/infrastructure endpoints
  defp skip_path?(%{path_info: ["metrics"]}), do: true
  defp skip_path?(%{path_info: ["health"]}), do: true
  defp skip_path?(_conn), do: false

  @doc """
  Gives back a password sign-in's charge to the per-IP auth bucket, for a
  sign-in whose password was right.

  The bucket is there to slow guessing, and a right password is not a guess:
  without the refund a classroom or a mobile carrier behind one address
  could sign in only `auth_limit` people a window. A wrong password keeps
  its charge, and the per-address lockout (`Gamend.Accounts.LoginLockouts`)
  also counts it, across every IP. The charge is taken before the password
  is checked, so guesses sent all at once are still held to the limit.

  A request this plug did not charge (rate limiting off, an exempt address,
  another path) gives nothing back, and a request gives back once. A refund
  that lands in the next window lowers that window's count instead: by the
  one slot the request took, so over the two windows the count is right.
  """
  @spec refund_login(Plug.Conn.t()) :: Plug.Conn.t()
  def refund_login(%Plug.Conn{private: %{@login_charge => {bucket, scale}}} = conn) do
    _count = GamendWeb.RateLimit.backend().inc(bucket, scale, -1)
    %{conn | private: Map.delete(conn.private, @login_charge)}
  end

  def refund_login(%Plug.Conn{} = conn), do: conn

  defp do_rate_limit(conn) do
    ip = client_ip(conn)
    routed = %{conn | path_info: routed_path(conn.path_info)}
    {bucket, scale, limit} = bucket_for(routed, ip)

    case GamendWeb.RateLimit.hit(bucket, scale, limit) do
      {:allow, _count} ->
        if password_login?(routed),
          do: put_private(conn, @login_charge, {bucket, scale}),
          else: conn

      {:deny, retry_after_ms} ->
        retry_secs = max(div(retry_after_ms, 1000), 1)
        # Who was throttled — a person, Googlebot, a scraper — for Admin → Geo.
        GeoCountry.record_rate_limited(conn)

        conn
        |> put_resp_header("retry-after", to_string(retry_secs))
        |> send_rate_limit_response(retry_secs)
        |> halt()
    end
  end

  defp send_rate_limit_response(%{path_info: [ApiSegment.api() | _]} = conn, _retry_secs) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(%{error: "Too Many Requests"}))
  end

  defp send_rate_limit_response(conn, retry_secs) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(429, rate_limit_html(retry_secs))
  end

  defp rate_limit_html(retry_secs) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="utf-8"><title>429 Too Many Requests</title>
    <style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#f9fafb;color:#111827}
    .c{text-align:center;max-width:400px;padding:2rem}.h{font-size:3rem;font-weight:700;color:#dc2626;margin:0}.m{margin-top:1rem;color:#6b7280}</style>
    </head>
    <body><div class="c"><p class="h">429</p><h1>Too Many Requests</h1>
    <p class="m">You have made too many requests. Please try again in #{retry_secs} seconds.</p>
    </div></body></html>
    """
  end

  # API login, device login and registration — stricter auth bucket
  defp bucket_for(%{path_info: [ApiSegment.api(), ApiSegment.v1(), path | _]} = _conn, ip)
       when path in @auth_paths do
    auth_bucket(ip)
  end

  # Polling for an OAuth session's result is not an auth attempt.
  #
  # It shared the 10/min auth bucket, while the shipped Godot client polls this
  # every 2 seconds for up to a minute — so any OAuth login that took longer
  # than about 18 seconds ran out of budget and the client reported a timeout,
  # on production defaults, for a sign-in that had actually succeeded. Reads of
  # a random 32-byte session id are cheap and idempotent; the general bucket is
  # the right home for them.
  defp bucket_for(
         %{path_info: [ApiSegment.api(), ApiSegment.v1(), RateLimitBucket.auth(), "session" | _]} =
           _conn,
         ip
       ) do
    {"general:#{ip}", setting(:general_window_ms), setting(:general_limit)}
  end

  # API OAuth endpoints — also auth bucket
  defp bucket_for(
         %{path_info: [ApiSegment.api(), ApiSegment.v1(), RateLimitBucket.auth() | _]} = _conn,
         ip
       ) do
    auth_bucket(ip)
  end

  # Browser login POST — same strict bucket as API login.
  #
  # Both spellings: the routes are `/users/log_in` and `/users/log_in/:token`,
  # so matching only the hyphenated form left browser password login in the
  # general bucket (240/min) instead of the auth one (10/min).
  #
  # Only the POST. Opening the page (a GET, the login form, the registration
  # form, a login link's landing) checks nothing, and counting it made every
  # browser sign-in cost two of the ten: one address got five a window.
  defp bucket_for(%{path_info: [ApiSegment.users(), action | _], method: @post} = _conn, ip)
       when action in @browser_auth_actions do
    auth_bucket(ip)
  end

  # Browser OAuth request/callback
  defp bucket_for(%{path_info: [RateLimitBucket.auth() | _]} = _conn, ip) do
    auth_bucket(ip)
  end

  # Client log uploads get their own bucket. They are legitimately more frequent
  # than ordinary API calls (a batch every few seconds per client) but must not
  # be able to fill a log store, and sharing the general bucket would mean a
  # device flushing diagnostics throttles its own gameplay requests.
  defp bucket_for(
         %{
           path_info: [ApiSegment.api(), ApiSegment.v1(), RateLimitBucket.client_logs() | _],
           method: @post
         } = _conn,
         ip
       ) do
    {"client_logs:#{ip}", setting(:client_logs_window_ms), setting(:client_logs_limit)}
  end

  defp bucket_for(_conn, ip) do
    {"general:#{ip}", setting(:general_window_ms), setting(:general_limit)}
  end

  defp auth_bucket(ip) do
    {"auth:#{ip}", setting(:auth_window_ms), setting(:auth_limit)}
  end

  # The sign-ins whose controller knows whether the password was right, and
  # gives the charge back when it was (`refund_login/1`): the API's email and
  # password, and the browser's form (a password or a login link's token).
  # Device login and registration make accounts, so they keep theirs.
  defp password_login?(%{
         method: @post,
         path_info: [ApiSegment.api(), ApiSegment.v1(), @password_login]
       }),
       do: true

  defp password_login?(%{method: @post, path_info: [ApiSegment.users(), action]})
       when action in @log_in_actions,
       do: true

  defp password_login?(_conn), do: false

  defp setting(key), do: Gamend.Settings.get(__MODULE__, key)

  # Real client IP is already extracted by the RealIp plug earlier in the
  # endpoint pipeline; IPv6 clients are bucketed by /64 (`RateLimit.ip_key/1`).
  defp client_ip(conn), do: GamendWeb.RateLimit.ip_key(conn.remote_ip)

  defp enabled?, do: setting(:enabled)
end
