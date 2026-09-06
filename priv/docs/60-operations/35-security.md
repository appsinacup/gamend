---
icon: hero-shield-check
---

# Security & Rate Limiting

Requests pass through a fixed chain in the endpoint: the real client IP is extracted from proxy headers, banned IPs are rejected, security headers are set, CORS is applied, and the request is rate-limited, all before the router runs. This guide covers each layer, what it protects against, and what to configure for production.

## The real client IP

Everything downstream (bans, rate limits, geo stats) keys on `conn.remote_ip`, so the first job is making that value true behind a proxy. `GamendWeb.Plugs.RealIp` reads, in priority order, `CF-Connecting-IP` (Cloudflare), `Fly-Client-IP` (Fly.io), then `X-Forwarded-For`, where it takes the last entry before the first trusted proxy, the one position an attacker cannot append to.

The headers are only parsed when the connecting peer *is* a trusted proxy (loopback and private ranges by default, extendable via the `trusted_proxies` config for `GamendWeb.Plugs.RealIp`). A request straight from the internet has its forwarding headers ignored entirely, so spoofing them buys nothing.

## IP bans

An IP ban is checked in ETS on every request: a banned address gets a bare `403` before any routing happens. Bans are persisted so they survive restarts, and broadcast over PubSub so every instance in a cluster applies them within moments of the ban being placed.

Ban and unban from [/admin/rate_limiting](/admin/rate_limiting) (permanent or with a TTL), or from server code:

```elixir
GamendWeb.Plugs.IpBan.ban("1.2.3.4")                    # permanent
GamendWeb.Plugs.IpBan.ban("1.2.3.4", :timer.hours(24))  # 24h
GamendWeb.Plugs.IpBan.unban("1.2.3.4")
```

## Rate limiting

HTTP requests are throttled per client IP, realtime messages per user, using Hammer counters. Each surface has its own bucket so one cannot starve another:

| Bucket | Scope | Default | Variables |
|---|---|---|---|
| General HTTP | per IP | 240 / 60s | `GAMEND_RATELIMIT_GENERAL_LIMIT`, `GAMEND_RATELIMIT_GENERAL_WINDOW_MS` |
| Auth (login, register, refresh, OAuth — API and browser) | per IP | 10 / 60s | `GAMEND_RATELIMIT_AUTH_LIMIT`, `GAMEND_RATELIMIT_AUTH_WINDOW_MS` |
| Client log uploads | per IP | 30 / 60s | `GAMEND_RATELIMIT_CLIENT_LOGS_LIMIT`, `GAMEND_RATELIMIT_CLIENT_LOGS_WINDOW_MS` |
| WebSocket channel messages | per user | 60 / 10s | `GAMEND_RATELIMIT_WS_LIMIT`, `GAMEND_RATELIMIT_WS_WINDOW_MS` |
| WebRTC DataChannel messages | per user | 300 / 10s | `GAMEND_RATELIMIT_DC_LIMIT`, `GAMEND_RATELIMIT_DC_WINDOW_MS` |
| ICE candidates | per user | 150 / 30s | `GAMEND_RATELIMIT_ICE_LIMIT`, `GAMEND_RATELIMIT_ICE_WINDOW_MS` |

`GAMEND_RATELIMIT_ENABLED` is the master switch. An HTTP client over the limit gets `429 Too Many Requests` with a `Retry-After` header; a WebSocket client over its budget has the channel closed with a `rate_limited` error, and a flooding WebRTC peer is disconnected. Separate daily quotas cap chat messages and chat reports per user (`GAMEND_LIMITS_MAX_CHAT_MESSAGES_PER_DAY`, `GAMEND_LIMITS_MAX_CHAT_REPORTS_PER_USER_PER_DAY`).

The default `ets` backend counts per node, which is fine for one instance and wrong for several: with N instances every limit is effectively N times higher. On multi-instance deployments set:

```bash
GAMEND_RATELIMIT_BACKEND=redis
GAMEND_RATELIMIT_REDIS_URL=redis://localhost:6379
```

Denied requests are counted in the `gamend_rate_limit_denies_total` metric, tagged by bucket; see [Metrics & Observability](/docs/observability). Live status and the IP-ban controls are on [/admin/rate_limiting](/admin/rate_limiting).

## Captcha

The register and magic-link forms can require a [Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/) challenge. These are the two paths that mail an address the submitter chose, where the abuse is not request volume (the rate limiter answers that) but a botnet spending your mail reputation an address at a time. Password login is deliberately not guarded, and the game SDKs never see the captcha: registration is browser-only and device login is untouched, so enabling it cannot break a shipped client.

```bash
GAMEND_CAPTCHA_ENABLED=true
GAMEND_CAPTCHA_SITE_KEY=0x4AAA...
GAMEND_CAPTCHA_SECRET_KEY=0x4AAA...
```

With the keys unset, dev and test fall back to Cloudflare's published dummy pair, which passes on any host. The widget stays on the page so form breakage shows up on the developer's machine, not in production. Verification fails *closed*: if Cloudflare is unreachable the submission is rejected, because treating an outage as a pass would make the protection removable by exactly the attacker positioned to cause one.

## Browser hardening

Every response carries baseline headers (`nosniff`, `SAMEORIGIN` framing, a strict referrer policy, a deny-by-default permissions policy, and same-origin resource policy), and every HTTPS response gets a one-year HSTS header. In production the `x-request-id` response header is stripped so internal correlation ids do not leak; the id stays available for log correlation.

Browser pages run under a strict Content-Security-Policy (no inline or third-party scripts). Two admin-only scopes carry their own slightly wider policies for Swagger UI and Oban Web, and when the captcha is enabled the policy is widened at request time to admit the Turnstile script, so deployments that never enable it keep exactly the strict policy.

## CORS

`GAMEND_HTTP_ALLOWED_ORIGINS` is the browser origin allowlist (prefix an entry with `regex:` for a pattern). Empty allows any origin *without credentials*: a token in an `Authorization` header still works from anywhere (which is how game clients authenticate) while cookies stay unusable cross-origin. Naming origins is what opts into credentialed requests. The same list gates WebSocket origins.

## Token and session revocation

Every JWT embeds the user's `token_version`. Changing a password or email, or calling `Gamend.Accounts.revoke_all_tokens/1`, bumps the version, which invalidates every previously issued access *and* refresh token in one write. There is no token blacklist to sweep. Operators do the same from [/admin/users](/admin/users) (revoke one token or all of a user's sessions), and [/admin/sessions](/admin/sessions) deletes live browser sessions individually or in bulk.

## TLS

Bandit serves HTTPS natively; no reverse proxy is required. Erlang's `:ssl` re-reads the certificate files from disk, so a renewed certificate is picked up without a restart, and the built-in ACME plug serves Let's Encrypt HTTP-01 challenges from a webroot (`GAMEND_TLS_ACME_WEBROOT`, matching certbot's `--webroot` mode) so issuance needs no nginx either.

```bash
GAMEND_TLS_CERTFILE=/etc/letsencrypt/live/example.com/fullchain.pem
GAMEND_TLS_KEYFILE=/etc/letsencrypt/live/example.com/privkey.pem
GAMEND_TLS_PORT=443
GAMEND_TLS_FORCE=true
```

`GAMEND_TLS_FORCE` redirects HTTP to HTTPS. It is off unless set: a host that serves port 80 itself keeps a plain-HTTP twin of every page until you enable it.

## Production checklist

- `GAMEND_AUTH_SECRET_KEY_BASE` set and secret; `GAMEND_AUTH_GUARDIAN_SECRET_KEY` if you want JWT signing separate from it.
- `GAMEND_RATELIMIT_BACKEND=redis` on anything with more than one instance.
- `GAMEND_HTTP_ALLOWED_ORIGINS` naming your web origins if browser players use cookies.
- `GAMEND_CAPTCHA_ENABLED=true` with real Turnstile keys once registration is public.
- TLS configured, and `GAMEND_TLS_FORCE=true` once HTTPS works.
- `GAMEND_OBSERVABILITY_METRICS_TOKEN` so `/metrics` is not world-readable; see [Metrics & Observability](/docs/observability).

## Reference

- **Every variable:** the [Settings guide](/docs/settings) — the Rate limiting, Captcha, TLS and Server & HTTP groups.
- **Admin pages:** [/admin/rate_limiting](/admin/rate_limiting), [/admin/users](/admin/users), [/admin/sessions](/admin/sessions).
- **Scaling:** the [Scaling guide](/docs/scaling) for running the Redis-backed limiter under Docker Compose.
