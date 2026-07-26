# Webhooks (signed, retried) + remote config

Design spec for the Phase 3 **Webhooks + remote config** item in
[ROADMAP.md](../../ROADMAP.md). **Depends on Jobs** (durable, retried delivery).
Two related integration features in one item — outbound **webhooks** (server →
your backend) and inbound-to-client **remote config** (server → your game).

The Oban config already reserves a **`webhooks: 10`** queue (added in Phase 0),
so the delivery lane exists; this item fills it.

---

# Part 1 — Webhooks (signed, retried)

Goal: let a host register HTTPS endpoints that receive server events —
`user.registered`, `purchase.completed`, `match.ended`, `quest.claimed`, … —
delivered reliably with retries/backoff and **HMAC-signed** so the receiver can
trust them.

## Why (this is the canonical reason Jobs exists)

The roadmap lists "reliable webhooks" as a headline justification for the job
queue: a webhook must survive a restart and shrug off a receiver's transient
5xx. `GameServer.Async` can't promise that; Oban can. Webhooks turn the server's
internal hook/event stream into an integration surface a host's own backend can
subscribe to without polling.

## Data model (both adapters)

- **`webhook_endpoints`** — `url` (https), `secret` (generated; used for
  signing), `events` (jsonb list of subscribed event names, or `["*"]`),
  `active`, `description`, `created_by`, timestamps.
- **`webhook_deliveries`** — the log: `endpoint_id`
  (`references(:webhook_endpoints, on_delete: :delete_all)`), `event`,
  `payload` (jsonb), `status` (`"pending"|"delivered"|"failed"`), `attempts`,
  `response_status`, `last_error`, `delivered_at`, `inserted_at`.
  Partial `index([:endpoint_id], where: "status = 'failed'")` for the failures
  view; `index([:endpoint_id, :inserted_at])` for the per-endpoint log.

## Delivery — `WebhookWorker` on the `webhooks` queue

- Events originate from the existing hook/context stream. A registry of
  **webhook-eligible events** (declared like notification-types/realtime-events)
  maps a lifecycle moment to an event name + payload builder. `Webhooks.emit(event, payload)`
  is the single entry point; plugins call it for custom events.
- `emit/2` looks up active endpoints subscribed to `event` and enqueues one
  `WebhookWorker` (`use Oban.Worker, queue: :webhooks, max_attempts: 8`) per
  endpoint — reliable fan-out with exponential backoff. **Enqueue happens after
  the originating transaction commits** (`defer/1`), never inside it.
- Each attempt POSTs the JSON payload with `req`, writing a `webhook_deliveries`
  row. Non-2xx or timeout ⇒ `{:error, _}` ⇒ Oban retries; attempts exhausted ⇒
  `status: failed` (kept in the log for manual replay).

## Signing (Stripe-style, verifiable)

Each request carries:

```
X-Gamend-Event: purchase.completed
X-Gamend-Timestamp: 1753200000
X-Gamend-Signature: sha256=<hex HMAC-SHA256(secret, "<timestamp>.<raw_body>")>
```

The receiver recomputes the HMAC over `timestamp.body` with the shared secret
and rejects a mismatch or a stale timestamp (replay guard). Secrets are shown
once on creation and rotatable.

## Security — SSRF guard

Because an admin supplies the URL, delivery **refuses non-HTTPS URLs and private
/loopback/link-local/metadata IP ranges** (validate at save *and* re-resolve at
send, since DNS can rebind). This matters more than usual: the server makes the
request, so an unguarded URL is an SSRF into the host's own network.

## Hooks (per CONTRIBUTING §Hooks)

- **`before_webhook_deliver(endpoint, event, payload)`** — pipeline hook to
  redact/transform a payload or veto delivery to a given endpoint. Six places
  (`@callback`+`@optional_callbacks`, `lifecycle_pipeline_hook?/2` +
  `normalize_pipeline_args/3`, `internal_hooks()`, `Hooks.Default`, SDK incl.
  `defoverridable`, docs). The worker runs it through `HookWorker`, so it's
  RPC-blocked automatically (Phase 0).

## Limits

`max_webhook_endpoints`, `max_webhook_events_per_endpoint`,
`max_webhook_payload_size`, `webhook_max_attempts` (retry budget).

---

# Part 2 — Remote config

Goal: server-managed values a **client** fetches and that change **without a
client update** — feature flags, tunables, seasonal toggles, balance numbers.

## Why (none of the existing config layers fit)

Three config-ish things already exist and none is this: `GameServer.Config` reads
plugin **env vars** (server-side, boot-time), `KV` is generic per-user/lobby
**storage**, and `Theme` is **site** theming. Remote config is the missing one:
a small, admin-curated, **client-read-only** key/value set delivered over the API
and pushed live when it changes.

## Data model

- **`remote_config`** — `key` (unique), `value` (jsonb, typed), `value_type`
  (`"bool"|"int"|"float"|"string"|"json"`), `description`, `active`, `version`
  (bumped on write, drives client caching), timestamps. `unique_index([:key])`.

## Client fetch + live update

- `GET /config` → `{values: %{...}, version: N}` with an **ETag** = version so a
  client can `304` cheaply. Only `active` keys are exposed.
- On any edit, bump `version` and broadcast `{:config_updated, version}` on a
  PubSub topic the `UserChannel` forwards as a `config_updated` event, so live
  clients refetch — the same subscribe/forward pattern notifications use
  (CONTRIBUTING §Web).
- Values are **read-only to clients**; there is no client write path.

## Hooks

- **`after_remote_config_changed(key, value)`** — observe (invalidate a
  derived cache, emit a webhook `config.changed`). Six places; deferred
  post-commit.

## Limits

`max_remote_config_keys`, `max_remote_config_value_size`,
`max_remote_config_key_len`.

---

## Admin (both parts)

- `admin_live/webhooks.ex` — endpoints CRUD (create shows the secret once,
  rotate secret), per-endpoint **delivery log** with response codes and a
  **replay** button (re-enqueues a `WebhookWorker`), failure filter.
- `admin_live/remote_config.ex` — key/value editor (typed inputs), toggle
  `active`, shows current `version`.
- `/admin` stat cards: active endpoints + failed-deliveries-24h; remote-config
  key count. Routes + nav + `admin_pages_render_test` entries.
- Admin API controllers with **parity**: manage endpoints, list/replay
  deliveries, CRUD config keys.

## "Update everywhere" — file list

- **README** Features: Webhooks + Remote config. **CHANGELOG** `[added]`
  Signed retried webhooks; `[added]` Remote config.
- **.env.example** — the `LIMIT_*` caps (queue size already in Oban config).
- **host_public_docs/** — new **Webhooks** page (event catalog, signature
  verification recipe, retry semantics) + **Remote config** page (fetch,
  ETag/version, live update); Data Schema gains the three tables; Server-scripting
  page gains `Webhooks.emit/2` + the hooks.
- **api_spec.ex** — feature list + `GET /config` (+ the `config_updated` realtime
  event; webhook payloads documented as an outbound catalog).
- **SDK** — `RemoteConfig` read stub + struct; `Webhooks` admin stubs; hooks
  mirrored; `gen.sdk`.
- **runtime_introspection.ex** — webhook stats (endpoints, `webhooks` queue
  depth, failure rate) + remote-config key count/version.
- **i18n** — 30 locales; **mix demo.seed** — a sample endpoint (Log/no-op URL),
  a few deliveries, and a handful of remote-config keys.

## Deferred / rejected

- **Inbound webhooks (receiving third-party callbacks): out of scope here.**
  Payment provider callbacks already have their own validated endpoints in
  `Payments`; this item is *outbound* only.
- **Audience targeting / A-B segmentation for remote config: defer.** v1 is a
  global key set; per-segment overrides ride on top later without changing the
  fetch contract.
- **Webhook payload schema versioning / transforms UI: defer.** The
  `before_webhook_deliver` hook covers custom shaping until there's demand for a
  declarative transform.

## Definition of done (CONTRIBUTING)

- [ ] Migrations for `webhook_endpoints` / `webhook_deliveries` / `remote_config`
      apply on SQLite **and** `GAMEND_DB_ADAPTER=postgres`; indexes as above.
- [ ] `Webhooks.emit/2` fan-out on the `webhooks` queue, HMAC-signed, SSRF-guarded,
      retried with backoff, logged; replay works. Enqueue deferred post-commit.
- [ ] `GET /config` with ETag/version; `config_updated` forwarded on the user
      channel; client-read-only.
- [ ] Paginated `list_*`/`count_*`; `Limits` caps enforced.
- [ ] Hooks `before_webhook_deliver` / `after_remote_config_changed` in all six
      places, RPC-blocked, SDK-mirrored.
- [ ] Admin pages (webhooks + config) + `/admin` cards + routes + nav +
      `admin_pages_render_test`; admin API parity.
- [ ] Docs, `.env.example`, CHANGELOG, README, `api_spec.ex`; i18n 30 locales.
- [ ] Tests: context + controller + admin + LiveView, both adapters; boot and
      actually deliver a signed webhook to a local test receiver, exhaust retries
      into `failed` + replay, and change a config key and see the client event.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
