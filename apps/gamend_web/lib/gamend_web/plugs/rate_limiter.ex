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

  setting(:enabled, :boolean,
    default: true,
    doc: "Master switch for all request/message throttling."
  )

  setting(:general_limit, :integer,
    default: 240,
    doc: "Max general HTTP requests per window, per IP."
  )

  setting(:general_window_ms, :integer,
    default: 60_000,
    doc: "General HTTP window, in milliseconds."
  )

  setting(:auth_limit, :integer,
    default: 10,
    doc: "Max login/register requests per window, per IP."
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
    if enabled?() and not skip_path?(conn) do
      do_rate_limit(conn)
    else
      conn
    end
  end

  # This plug runs before `LocalePath` (so before the body is parsed), and so
  # sees `/ro/users/log_in` where the router will see `/users/log_in`: strip the
  # locale here, or a localized login would count against the general bucket.
  defp routed_path(["api" | _] = path_info), do: path_info
  defp routed_path(path_info), do: LocalePath.strip_locale(path_info)

  # Skip rate limiting for internal/infrastructure endpoints
  defp skip_path?(%{path_info: ["metrics"]}), do: true
  defp skip_path?(%{path_info: ["health"]}), do: true
  defp skip_path?(_conn), do: false

  defp do_rate_limit(conn) do
    ip = client_ip(conn)
    {bucket, scale, limit} = bucket_for(%{conn | path_info: routed_path(conn.path_info)}, ip)

    case GamendWeb.RateLimit.hit(bucket, scale, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after_ms} ->
        retry_secs = max(div(retry_after_ms, 1000), 1)

        conn
        |> put_resp_header("retry-after", to_string(retry_secs))
        |> send_rate_limit_response(retry_secs)
        |> halt()
    end
  end

  defp send_rate_limit_response(%{path_info: ["api" | _]} = conn, _retry_secs) do
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

  # API login/registration/refresh — stricter auth bucket
  defp bucket_for(%{path_info: ["api", "v1", path | _]} = _conn, ip)
       when path in ~w(login register refresh) do
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
  defp bucket_for(%{path_info: ["api", "v1", "auth", "session" | _]} = _conn, ip) do
    {"general:#{ip}", setting(:general_window_ms), setting(:general_limit)}
  end

  # API OAuth endpoints — also auth bucket
  defp bucket_for(%{path_info: ["api", "v1", "auth" | _]} = _conn, ip) do
    auth_bucket(ip)
  end

  # Browser login POST — same strict bucket as API login.
  #
  # Both spellings: the routes are `/users/log_in` and `/users/log_in/:token`,
  # so matching only the hyphenated form left browser password login in the
  # general bucket (240/min) instead of the auth one (10/min).
  defp bucket_for(%{path_info: ["users", action | _], method: method} = _conn, ip)
       when action in ~w(log_in log-in register) and method in ["POST", "GET"] do
    auth_bucket(ip)
  end

  # Browser OAuth request/callback
  defp bucket_for(%{path_info: ["auth" | _]} = _conn, ip) do
    auth_bucket(ip)
  end

  # Client log uploads get their own bucket. They are legitimately more frequent
  # than ordinary API calls (a batch every few seconds per client) but must not
  # be able to fill a log store, and sharing the general bucket would mean a
  # device flushing diagnostics throttles its own gameplay requests.
  defp bucket_for(%{path_info: ["api", "v1", "client_logs" | _], method: "POST"} = _conn, ip) do
    {"client_logs:#{ip}", setting(:client_logs_window_ms), setting(:client_logs_limit)}
  end

  defp bucket_for(_conn, ip) do
    {"general:#{ip}", setting(:general_window_ms), setting(:general_limit)}
  end

  defp auth_bucket(ip) do
    {"auth:#{ip}", setting(:auth_window_ms), setting(:auth_limit)}
  end

  defp setting(key), do: Gamend.Settings.get(__MODULE__, key)

  # Real client IP is already extracted by the RealIp plug earlier in the
  # endpoint pipeline; IPv6 clients are bucketed by /64 (`RateLimit.ip_key/1`).
  defp client_ip(conn), do: GamendWeb.RateLimit.ip_key(conn.remote_ip)

  defp enabled?, do: setting(:enabled)
end
