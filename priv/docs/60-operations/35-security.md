---
icon: hero-shield-check-solid
---

# Security & Rate Limiting

Requests pass through a fixed chain in the endpoint: security headers are set and static files are served first, then the real client IP is extracted from proxy headers, banned IPs are rejected, CORS is applied, and the request is rate-limited, all before the request body is parsed and before the router runs. A request over its limit is refused without its body being read. This guide covers each layer, what it protects against, and what to configure for production.

## The real client IP

Everything downstream (bans, rate limits, geo stats) keys on `conn.remote_ip`, so the first job is making that value true behind a proxy. `GamendWeb.Plugs.RealIp` reads, in priority order, `CF-Connecting-IP` (Cloudflare), `Fly-Client-IP` (Fly.io), then `X-Forwarded-For`, where it takes the last entry before the first trusted proxy, the one position an attacker cannot append to.

The headers are only parsed when the connecting peer *is* a trusted proxy (loopback and private ranges by default, extendable via the `trusted_proxies` config for `GamendWeb.Plugs.RealIp`). A request straight from the internet has its forwarding headers ignored entirely, so spoofing them buys nothing.

The server listens on `::`, so a proxy reaching it over IPv4 connects as `::ffff:a.b.c.d` and is judged as that IPv4 address. From such a proxy only `X-Forwarded-For` is read: Caddy and nginx pass `CF-Connecting-IP` and `Fly-Client-IP` on as the client sent them.

## IP bans

An IP ban is checked in ETS on every request that reaches it: a banned address gets a bare `403` before any routing happens. An IPv6 address is banned by its /64 network, since one subscriber is usually given a whole /64 and can move around inside it; `ban("2001:db8::1")` is listed as `2001:db8::/64`. An IPv4 address is banned as itself. Static files are served earlier in the chain, so a ban does not cover them.

IP bans are `Gamend.Bans` rows of kind `:ip`, the table every ban lives in: each has an optional end, a reason, and who placed it. A ban is broadcast over PubSub so every instance in a cluster applies it within moments, and its row is kept after it ends (lifted or expired) as history, deleted by retention after `GAMEND_RETENTION_BANS_DAYS` (365). Banning an address that is already banned replaces its ban.

Ban and unban from [/admin/bans](/admin/bans) (a preset from 10 minutes to permanent or a number of days, and a reason), from the admin API (`GET`/`POST /api/v1/admin/bans`, `DELETE /api/v1/admin/bans/:id`), or from server code:

```elixir
GamendWeb.Plugs.IpBan.ban("1.2.3.4")                    # permanent
GamendWeb.Plugs.IpBan.ban("1.2.3.4",                    # 24h
  expires_at: Gamend.Bans.expires_after(:timer.hours(24)),
  reason: "Scraping"
)
GamendWeb.Plugs.IpBan.unban("1.2.3.4")
```

## Account bans

(Every ban, chat mutes included, is a `Gamend.Bans` row; mutes are described in the [Chat guide](/docs/chat#mutes).)

An account ban (`Gamend.Bans`, kind `:account`) keeps a player out of the game while letting them see why. A banned account still signs in, refreshes its token and signs out; `GET /api/v1/me` carries its `ban` (`expires_at`, null for permanent, and `reason`), and it can delete itself. Everything else refuses it:

- **API**: every authenticated call answers 403 `account_banned` (`GamendWeb.Plugs.AccountBan`, in the `:api_auth` and `:api_optional_auth` pipelines; a personal API token too).
- **Socket**: it connects and joins its own user channel, which carries `account_banned` and `account_unbanned`, and nothing else; the user channel refuses its hook calls, KV subscriptions and WebRTC.
- **Website**: every LiveView sends it to `/suspended` (until when, why, a way to its settings and to log out), its settings excepted, and so does a controller route that needs a signed-in account (`GamendWeb.UserAuth.require_authenticated_user/2`, a host's own included); a plain page shows a notice leading there.

A ban placed while the account is connected closes its sockets and open pages within a second (`GamendWeb.AccountBanKicks`), and they reconnect into those limits. An admin account cannot be banned, so no admin can lock another out of the console.

A ban with an end schedules a job at that time (`Gamend.Bans.ExpiryWorker`), so a ban running out is told like a lift: `account_unbanned` on the user channel and the `after_ban_lifted` hook. The ban stops counting at its end whether or not the job has run. Plugins hear of every ban through `after_ban_created` and `after_ban_lifted` (see [Server scripting](/docs/server-scripting)).

Place and lift one on [/admin/bans](/admin/bans) or a user's editor on [/admin/users](/admin/users), through the admin API (`POST /api/v1/admin/bans` with `kind: "account"` and `user_id`), or from code (a plugin passes `source: :plugin`):

```elixir
Gamend.Bans.ban(:account, user.id,
  expires_at: DateTime.add(DateTime.utc_now(), 7, :day),
  reason: "Cheating",
  source: :plugin
)
Gamend.Bans.lift(:account, user.id)
```

## Rate limiting

HTTP requests are throttled per client IP (an IPv6 client per /64, for the same reason as bans), realtime messages per user, using Hammer counters. Each surface has its own bucket so one cannot starve another:

| Bucket | Scope | Default | Variables |
|---|---|---|---|
| General HTTP | per IP | 240 / 60s | `GAMEND_RATELIMIT_GENERAL_LIMIT`, `GAMEND_RATELIMIT_GENERAL_WINDOW_MS` |
| Auth (login, register, refresh, OAuth — API and browser) | per IP | 10 / 60s | `GAMEND_RATELIMIT_AUTH_LIMIT`, `GAMEND_RATELIMIT_AUTH_WINDOW_MS` |
| Client log uploads | per IP | 30 / 60s | `GAMEND_RATELIMIT_CLIENT_LOGS_LIMIT`, `GAMEND_RATELIMIT_CLIENT_LOGS_WINDOW_MS` |
| WebSocket channel messages | per user | 60 / 10s | `GAMEND_RATELIMIT_WS_LIMIT`, `GAMEND_RATELIMIT_WS_WINDOW_MS` |
| WebRTC DataChannel messages | per user | 300 / 10s | `GAMEND_RATELIMIT_DC_LIMIT`, `GAMEND_RATELIMIT_DC_WINDOW_MS` |
| ICE candidates | per user | 150 / 30s | `GAMEND_RATELIMIT_ICE_LIMIT`, `GAMEND_RATELIMIT_ICE_WINDOW_MS` |
| Peer-to-peer signaling messages | per user | 300 / 10s | `GAMEND_RATELIMIT_SIGNALING_WS_LIMIT`, `GAMEND_RATELIMIT_SIGNALING_WS_WINDOW_MS` |
| Peer-to-peer ICE candidates | per user | 150 / 30s | `GAMEND_RATELIMIT_SIGNALING_ICE_LIMIT`, `GAMEND_RATELIMIT_SIGNALING_ICE_WINDOW_MS` |

`GAMEND_RATELIMIT_ENABLED` is the master switch. An HTTP client over the limit gets `429 Too Many Requests` with a `Retry-After` header; a WebSocket client over its budget has the channel closed with a `rate_limited` error, and a flooding WebRTC peer is disconnected. Separate daily quotas cap chat messages and chat reports per user (`GAMEND_LIMITS_MAX_CHAT_MESSAGES_PER_DAY`, `GAMEND_LIMITS_MAX_CHAT_REPORTS_PER_USER_PER_DAY`).

The default `ets` backend counts per node, which is fine for one instance and wrong for several: with N instances every limit is effectively N times higher. On multi-instance deployments set:

```bash
GAMEND_RATELIMIT_BACKEND=redis
GAMEND_RATELIMIT_REDIS_URL=redis://localhost:6379
```

Denied requests are counted in the `gamend_rate_limit_denies_total` metric, tagged by bucket; see [Metrics & Observability](/docs/observability). Live status and the IP-ban controls are on [/admin/rate_limiting](/admin/rate_limiting).

## Captcha

The register and magic-link forms can require a [Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/) challenge. These are the two paths that mail an address the submitter chose, where the abuse is not request volume (the rate limiter answers that) but a botnet spending your mail reputation an address at a time. Password login is deliberately not guarded, and the game SDKs never see the captcha unless you ask: `POST /api/v1/register` is guarded only with `GAMEND_CAPTCHA_API_REGISTER=true`, and device login never is, so enabling it cannot break a shipped client.

```bash
GAMEND_CAPTCHA_ENABLED=true
GAMEND_CAPTCHA_SITE_KEY=0x4AAA...
GAMEND_CAPTCHA_SECRET_KEY=0x4AAA...
```

With the keys unset, dev and test fall back to Cloudflare's published dummy pair, which passes on any host. The widget stays on the page so form breakage shows up on the developer's machine, not in production. Verification fails *closed*: if Cloudflare is unreachable the submission is rejected, because treating an outage as a pass would make the protection removable by exactly the attacker positioned to cause one.

## Browser hardening

Every response carries baseline headers (`nosniff`, `SAMEORIGIN` framing, a strict referrer policy, a deny-by-default permissions policy, and same-origin resource policy), and every HTTPS response gets a one-year HSTS header. In production the `x-request-id` response header is stripped so internal correlation ids do not leak; the id stays available for log correlation.

Browser pages run under a strict Content-Security-Policy (no inline or third-party scripts). Two scopes carry their own slightly wider policies: Swagger UI at `/api/docs`, which is public unless `GAMEND_FEATURES_OPENAPI=false`, and the admin-only Oban Web. When the captcha is enabled the policy is widened at request time to admit the Turnstile script, so deployments that never enable it keep exactly the strict policy.

## CORS

`GAMEND_HTTP_ALLOWED_ORIGINS` is the browser origin allowlist (prefix an entry with `regex:` for a pattern). Empty allows any origin *without credentials*: a token in an `Authorization` header still works from anywhere (which is how game clients authenticate) while cookies stay unusable cross-origin. Naming origins is what opts into credentialed requests.

The same list gates WebSocket origins. The game socket (`/socket`) signs in by token, so with the list empty it takes any origin, like the API. The pages' socket (`/live`) signs in by the session cookie, so it always keeps to the server's own names (`GAMEND_HTTP_HOST`, `GAMEND_HTTP_OTHER_HOSTS`) plus the list.

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

- **Every variable:** the [Settings guide](/docs/settings) — the Rate limiting, Captcha, TLS & certificates and Server & HTTP groups.
- **Admin pages:** [/admin/bans](/admin/bans), [/admin/rate_limiting](/admin/rate_limiting), [/admin/users](/admin/users), [/admin/sessions](/admin/sessions).
- **Scaling:** the [Scaling guide](/docs/scaling) for running the Redis-backed limiter under Docker Compose.
