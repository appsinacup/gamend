# Event-tracking API → Postgres `events` table

Design spec for the Phase 3 **Event-tracking API** item in
[ROADMAP.md](../../ROADMAP.md). Deliberately small (effort **S**) — it's the
capture pipeline that a later ClickHouse/PostHog graduation plugs into, not the
analytics product itself.

Goal: a generic endpoint that ingests **per-player analytics events**
(`level_started`, `item_purchased`, `tutorial_step`, …) into a Postgres `events`
table — server-enriched, batched, rate-limited, and auto-pruned.

## Why (Prometheus can't do per-player; store in PG before ClickHouse)

The roadmap is explicit: **capture the events in Postgres first**, and only move
to ClickHouse/PostHog when volume forces it. PromEx/Prometheus is aggregate *ops*
metrics — it cannot answer "what did *this* player do before they churned." The
real work is the **capture pipeline**, and its schema is deliberately portable so
the eventual ClickHouse/PostHog step is a sink swap, not a rewrite.

## Data model (Postgres-first, volume-aware)

- **`events`** — `id` (**UUIDv7** — time-ordered, so inserts stay clustered and
  time-range scans are cheap), `user_id` (nullable — anonymous sessions),
  `session_id`, `name` (event name), `properties` (jsonb, game-defined),
  `context` (jsonb — platform, app_version, locale, country), `occurred_at`
  (client clock), `inserted_at` (server clock, the trusted time).
- **Indexing is minimal on purpose** — every index taxes ingest. Ship
  `index([:name, :inserted_at])` and `index([:user_id, :inserted_at], where: "user_id IS NOT NULL")`;
  the UUIDv7 PK already orders by time. Add more only when a query proves it needs
  one.
- **SQLite note:** the table works on SQLite too (dev/single-node), but the
  feature is Postgres-shaped; document that heavy analytics implies
  `GAMEND_DB_ADAPTER=postgres`.

## Ingestion — batched, enriched, never client-trusted

- `POST /events` (one) and `POST /events/batch` (array — clients buffer locally
  and flush). Both auth-optional (anonymous events carry only `session_id`).
- The server **overwrites** the trusted fields: `user_id` from the auth token
  (never the body), `inserted_at` server-side, `context.country` from the request
  IP. A client cannot attribute events to another user or backdate them.
- **Batched writes:** a supervised `GameServer.Events.Writer` GenServer buffers
  incoming events and flushes with a single `Repo.insert_all` every N ms or M
  rows — turning an ingest burst into one round-trip (the same coalescing logic
  that motivates `realtime_debounce_ms`). Added to the host supervision tree
  **and** the starter repo's tree (CONTRIBUTING §Functionality).
- **Rate-limited** per user/IP (`max_events_per_user_per_day`, reusing the
  rolling-window limiter chat uses) and per-batch (`max_events_per_batch`).

## Retention — mandatory, or the table eats the disk

A durable `GameServer.Schedule` job prunes events older than
`event_retention_days` (config, default e.g. 90). This is not optional: an
analytics table without retention grows unbounded. Pruning is a ranged
`DELETE ... WHERE inserted_at < cutoff` on the time index.

## Server-side emission

Contexts/hooks can call `Events.track(name, user_id, properties)` to fold
lifecycle moments (registration, purchase, match end) into the same stream — one
unified event log for client- and server-originated activity.

## Hooks (per CONTRIBUTING §Hooks)

- **`before_event_track(event)`** — pipeline hook to **drop/sample/scrub** an
  event (PII redaction, sampling to cut volume, dynamic allow-list). Runs cheaply
  in-process as part of the ingest pipeline (add to `lifecycle_pipeline_hook?/2` +
  `normalize_pipeline_args/3`). Six places, RPC-blocked, SDK-mirrored.
- **No per-event `after_*` hook by design** — at analytics volume, fanning a hook
  per event is a footgun; downstream consumers subscribe to the *batch/sink*
  (webhooks, or the future ClickHouse sink), not individual rows.

## Limits / config

`max_event_name_len`, `max_event_properties_size`, `max_events_per_batch`,
`max_events_per_user_per_day`, `event_retention_days`. `EVENT_TRACKING_ENABLED`
toggle (default on) so a host can disable capture entirely.

## Web / API

- `POST /events`, `POST /events/batch` — ingest.
- **No public read** of the raw stream (privacy) — reads are admin-only.
  A per-user "my events" export can come later if a data-portability need arises.

## Admin

- `admin_live/events.ex` — an events explorer (filter by name/user/time-range,
  paginated, shows names not raw UUIDs) + a simple **events-per-name-per-day**
  count view (the "is data flowing?" dashboard, not a BI tool).
- `/admin` stat card (events today, distinct names, table size / retention
  window) + route + nav + `admin_pages_render_test`.
- Admin API parity: query events, counts, trigger a prune.

## "Update everywhere" — file list

- **README** Features: Event tracking. **CHANGELOG** `[added]` Event-tracking API.
- **.env.example** — `EVENT_TRACKING_ENABLED`, `LIMIT_*` caps, retention days.
- **host_public_docs/** — new Event-tracking page (ingest shape, batching,
  server-enrichment, retention, "graduate to ClickHouse later"); Data Schema
  gains `events`.
- **api_spec.ex** — feature list + the ingest endpoints.
- **SDK** — `Events` stub (`track`, `flush`) + struct; a client-side batching
  helper is a nice-to-have; `@sdk_modules`, `gen.sdk`; hook mirrored.
- **runtime_introspection.ex** — event stats (today, by name, table size,
  writer buffer depth).
- **i18n** — 30 locales; **mix demo.seed** — seed a spread of events across a few
  names/days so the explorer + counts show a trend.

## Deferred / rejected

- **ClickHouse/PostHog now: no** (roadmap "Later"). This item is the capture
  layer; the sink swap comes when volume forces it. The schema is kept portable
  precisely so that's cheap.
- **In-app funnels / retention charts / cohorts: defer.** That's the analytics
  product — out of scope; the admin view is just "data is flowing."
- **Client-readable event stream: rejected.** Raw per-player events are
  sensitive; reads stay admin-only.

## Definition of done (CONTRIBUTING)

- [ ] `events` migration applies on SQLite **and** `GAMEND_DB_ADAPTER=postgres`;
      minimal time-ordered indexes as above.
- [ ] Batched `insert_all` writer supervised in both trees; server-side
      enrichment overrides client-supplied `user_id`/time/country; rate limits +
      caps enforced; retention prune on Schedule.
- [ ] `before_event_track` hook in all six places, RPC-blocked, SDK-mirrored;
      no per-event after-hook (documented rationale).
- [ ] Admin explorer + counts + `/admin` card + route + nav +
      `admin_pages_render_test`; admin API parity (query/prune).
- [ ] Docs, `.env.example`, CHANGELOG, README, `api_spec.ex`; i18n 30 locales.
- [ ] Tests: context + controller (single + batch) + admin + LiveView, both
      adapters; boot and actually ingest a batch, confirm enrichment + rate
      limit, and prune old events.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
