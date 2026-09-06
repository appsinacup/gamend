---
icon: hero-chart-bar
---

# Metrics & Observability

The server exposes three windows into itself: Prometheus metrics at `/metrics`, a live log view in the admin console backed by a ring buffer and an optional rotating file, and a small set of public stats endpoints. Together they answer "is it up", "what is it doing", and "what just happened" without attaching a debugger to production.

## Prometheus metrics

`/metrics` is a PromEx endpoint scraped by Prometheus (or Grafana Agent). It auto-instruments the layers you did not write, plus two custom plugins for the ones you did:

| Plugin | What it exports |
|---|---|
| BEAM | VM memory, schedulers, atoms, processes, ports, ETS |
| Phoenix | HTTP request count, duration and status by route |
| Ecto | Query count, duration and queue time per source |
| Application | App version, git SHA, uptime |
| Geo | `gamend_geo_requests_total` — requests by ISO country code (`XX` for unknown) |
| Cache | `gamend_cache_reads_total` (hit/miss by key prefix), `gamend_rate_limit_denies_total` (by bucket), `gamend_async_overload_total` |

### Gating the endpoint

`/metrics` reveals routes, traffic volumes and error rates, so it is gated: loopback always scrapes freely, and once `GAMEND_OBSERVABILITY_METRICS_TOKEN` is set, every non-loopback request (including private and Docker-internal addresses) must send `Authorization: Bearer <token>`. The setting accepts the token inline or a path to a file holding it (a docker secret). With no token configured, private-range addresses are allowed without auth as a dev/compose convenience.

```yaml
scrape_configs:
  - job_name: "gamend"
    bearer_token: "my-secret-prometheus-token"
    static_configs:
      - targets: ["app:4000"]
```

### Grafana

`docker compose up` starts Prometheus (scraping `/metrics` every 15s) and Grafana at `localhost:3000`, with provisioning that auto-adds the Prometheus data source and a "Gamend" dashboard folder. PromEx renders the standard BEAM, Phoenix and Ecto dashboards for that setup. If you host Grafana elsewhere, set `GAMEND_OBSERVABILITY_GRAFANA_URL` and the admin dashboard links to it.

## Logs

Recent log entries land in an in-memory ring buffer (the last 5,000, written straight to ETS so a log storm never serializes through a process) and are browsable live at [/admin/logs](/admin/logs), filterable by level, module, text, and by *source*: game clients can upload their own logs, which are re-emitted through the server's logger, so the source filter is what keeps the server's tail from being buried under every connected player's entries. A client session id joins a client's lines to the server lines logged while handling its requests. Client-side collection is its own system; see the [Client logs guide](/docs/client-logs).

The buffer is in-memory only and lost on restart. For history that survives a redeploy, point the rotating file handler at persistent storage. It runs alongside stdout, so platform log drains still receive everything:

```bash
GAMEND_OBSERVABILITY_LOG_FILE_PATH=/data/log/gamend.log
GAMEND_OBSERVABILITY_LOG_FILE_LEVEL=info
GAMEND_OBSERVABILITY_LOG_FILE_MAX_BYTES=10000000   # per file
GAMEND_OBSERVABILITY_LOG_FILE_MAX_FILES=5          # ~50MB total
```

`GAMEND_OBSERVABILITY_LOG_LEVEL` sets the application level, and `GAMEND_OBSERVABILITY_ACCESS_LOG_LEVEL` controls per-request access logs (`off` silences them).

## Health

`GET /api/v1/health` is unauthenticated and returns `{"status": "ok"}` with a timestamp. Point load-balancer and uptime checks at it.

## Public stats

With `GAMEND_FEATURES_PUBLIC_STATS` on (the default), the unauthenticated endpoints `GET /api/v1/stats`, `/users/stats`, `/lobbies/stats`, `/parties/stats`, `/quests/stats`, `/signaling/stats` and `/matchmaking/stats` return aggregate counts, never per-row data, and the [/stats](/stats) page renders the same snapshot in the browser. The admin index, the page and the API all read one cached composition, so every surface shows one set of numbers. They do reveal how busy the server is; the flag closes the page and the endpoints together.

## In the admin console

[/admin/system](/admin/system) (uptime, schedulers, BEAM memory breakdown, ETS tables), [/admin/connections](/admin/connections) (live sockets per node), [/admin/geo](/admin/geo) (traffic by country), [/admin/analytics](/admin/analytics) (DAU and retention cohorts) and [/admin/dashboard](/admin/dashboard) (Phoenix LiveDashboard) show much of the same telemetry without a Prometheus stack; see the [Admin Console guide](/docs/admin-console).

## Reference

- **Client logs:** [/docs/client-logs](/docs/client-logs) — collecting logs from game clients into `/admin/logs`.
- **Load testing:** [/docs/load-testing](/docs/load-testing) — watching these metrics while generating load.
- **Performance:** [/docs/performance](/docs/performance) — what the numbers should look like and what to tune.
- **Settings:** the Observability group in the [Settings guide](/docs/settings).
