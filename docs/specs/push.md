# Push — server delivery + push-token storage

Design spec for the Phase 1 **Push** item in [ROADMAP.md](../../ROADMAP.md).
Format and rigor mirror the Phase 0 sections: what ships, the concrete
architecture, and the full CONTRIBUTING checklist it must satisfy.

Goal: let the server deliver push notifications to a user's devices, reliably
and provider-agnostically. Two halves ship here:

1. **Push-token storage** — devices register their FCM/APNs token against the
   authenticated user; a user has many devices.
2. **Server delivery** — `GameServer.Push.send_to_user/3` fans a message out to
   those tokens over the durable job queue, retrying transient provider errors
   and pruning tokens the provider reports dead.

The Godot-side client work ("Push — Godot client") is a **separate** Phase 1
item; this item is the server contract it targets.

## Why (rides on Jobs; completes the notification story)

Today `GameServer.Notifications` reaches only *connected* clients — a row is
written and a PubSub event fires, so a user who isn't holding a WebSocket open
never learns anything happened. Push closes that gap: it's the one delivery
channel that works when the app is backgrounded or killed. It's placed right
after Phase 0 because reliable fan-out is exactly what the job queue exists for
— a broadcast to a group/party/all-users must survive restarts and transient
5xx from the provider, which `GameServer.Async` cannot promise.

## Delivery via Pigeon

Provider transport is **[Pigeon 2.x](https://hex.pm/packages/pigeon)** in
`apps/game_server_core/mix.exs`, the maintained Elixir push library — pinned
to the post-2.0.1 main-branch ref that replaced kadabra+httpoison with Mint
(#296): the hex release's httpoison dependency conflicts with
`ueberauth_steam_strategy`'s `~> 3.0` pin, and the Mint rewrite is the
architecture we want anyway. Re-point at hex on the next release. What it buys:

- **APNs over HTTP/2 on Mint** — the same HTTP/2 engine already in this tree
  (under `finch`), with connection lifecycle Pigeon owns: pings (10-min
  default), GOAWAY handling, reconnects.
- **Auth handled** — the APNs ES256 `.p8` JWT is minted and refreshed by
  Pigeon's token worker; the FCM OAuth bearer comes from a `Goth` worker we
  supervise. No hand-rolled JWT caching.
- **Battle-tested error mapping** — provider responses arrive as atoms on the
  notification (`:success`, `:unregistered`, `:bad_device_token`, …) instead of
  raw status codes we'd have to map ourselves.
- **`Pigeon.Sandbox`** — a test adapter that echoes back preset responses, so
  dead-token and retry paths are testable without mocking HTTP.

Accepted costs, eyes open: Pigeon hard-requires `goth` and `joken` (`joken`
duplicates `jose`, which stays for Apple sign-in secrets — two JWT libs in the
binary), and its dispatchers are supervised processes. The zero-config
requirement still holds: dispatchers are started **only when their env vars are
present** (see Dispatchers below), so the default build boots with no push
config and routes everything to `Log`.

## Provider model — routed per token, not one global switch

A behaviour `GameServer.Push.Provider` — kept as our seam over Pigeon, so the
`Log` adapter, tests, and any future transport swap all sit behind one
contract. Delivery is one message to one token (matching the one-job-per-token
worker), and the error class is decided by the provider, where the
provider-specific response taxonomy lives:

```elixir
@callback deliver(Message.t(), PushToken.t()) ::
            :ok | {:invalid, atom()} | {:error, :transient | :permanent, term()}
@callback configured?() :: boolean()
```

Three adapters ship:

- **`GameServer.Push.Providers.Log`** — the default (dev/test). Logs each
  message instead of calling out, so the whole flow runs with zero credentials
  — the `Storage.Local` of push. Returns `{:ok, token}` for every token.
- **`GameServer.Push.Providers.FCM`** — Firebase Cloud Messaging **HTTP v1**,
  for **Android and Web** (and it can still relay iOS if you'd rather not run
  APNs). Builds a `Pigeon.FCM.Notification` (`{:token, token}` target,
  `notification` map from title/body/image, `data` map) and calls
  `Pigeon.push(GameServer.Push.FCMDispatcher, notif)`.
- **`GameServer.Push.Providers.APNs`** — **direct to Apple** for **iOS**.
  Builds a `Pigeon.APNS.Notification` (alert from title/body, topic from
  `APNS_TOPIC`, `put_badge`/`put_sound`/`put_collapse_id`/`put_custom` for the
  rest) and calls `Pigeon.push(GameServer.Push.APNSDispatcher, notif)`.

**Routing.** Unlike the single-switch Storage adapter, Push routes **per token**
off the `push_tokens.provider` column: `"fcm"` → FCM, `"apns"` → APNs. A
provider whose `configured?/0` is false (dispatcher not running) — and the
global `GAMEND_PUSH_ADAPTER=log` override — both fall through to `Log`. So: no config
→ dev logs everything; configure only `PUSH_FCM_*` → iOS tokens registered as
`fcm` relay through Google; configure `APNS_*` too → iOS tokens registered as
`apns` go straight to Apple.

**Response classification** (in each adapter's `deliver/2`):

| Pigeon response | Result | Worker action |
|-----------------|--------|---------------|
| `:success` | `{:ok, token}` | bump `last_used_at` |
| APNs `:unregistered`, `:bad_device_token`; FCM `:unregistered`, `:invalid_argument` | `{:invalid, token}` | `disable_token/1` (payload is pre-validated by `Limits`, so FCM `:invalid_argument` means a bad token) |
| FCM `:sender_id_mismatch`, `:third_party_auth_error` | `{:error, token, reason}` permanent | log loudly, no retry — it's a config error, retrying can't fix it |
| everything else (`:timeout`, `:too_many_requests`, 5xx-family, connection errors) | `{:error, token, reason}` transient | Oban retries with backoff |

## Dispatchers & supervision

Two dispatcher modules in `apps/game_server_core/lib/game_server/push/`:

```elixir
defmodule GameServer.Push.FCMDispatcher do
  use Pigeon.Dispatcher, otp_app: :game_server_core
end

defmodule GameServer.Push.APNSDispatcher do
  use Pigeon.Dispatcher, otp_app: :game_server_core
end
```

- Config lives under
  `config :game_server_core, GameServer.Push.FCMDispatcher, ...` (and `APNS...`),
  set by `host_runtime.exs` from env — same pattern as the `GAMEND_STORAGE_ADAPTER`
  case block.
- **FCM** needs a Goth worker: `{Goth, name: GameServer.Push.Goth, source:
  {:service_account, decoded_credentials}}`, started **before** the FCM
  dispatcher; the dispatcher gets `adapter: Pigeon.FCM, auth:
  GameServer.Push.Goth, project_id: ...`.
- **APNs**: `adapter: Pigeon.APNS, key:, key_identifier:, team_id:, mode:`
  (`:prod`/`:dev` from `APNS_ENV`). Token auth only — no `.p12` certs.
- All push processes live under one **`GameServer.Push.Supervisor`** subtree
  in `GameServerWeb.HostSupervision.children()` (before Oban, so dispatchers
  are up when push-queue workers start). The supervisor is always present but
  builds its **children** from config: Goth + FCM dispatcher only when the FCM
  vars are set, APNS dispatcher only when the APNs vars are set, none under
  `GAMEND_PUSH_ADAPTER=log` — zero config supervises nothing. The starter repo builds
  its tree from `HostSupervision.children()`, so it inherits the child on its
  next dep bump with no change of its own. The subtree has
  its own restart budget, so a crash-looping dispatcher exhausts *its*
  supervisor, not the app's — push degrades to `Log` routing (see
  `configured?/0`) while the rest of the server keeps running.
- **Credentials are parse-validated at boot** in `host_runtime.exs`: an
  unreadable `.p8` key or unparseable service-account JSON logs one loud error
  and leaves that dispatcher unconfigured (→ `Log` fallback) instead of
  handing Pigeon a config it will crash-loop on. Runtime crashes are then
  transient-network territory, which Pigeon's dispatchers reconnect through
  without dying.
- `configured?/0` is a liveness check: `Process.whereis(dispatcher) != nil`.
- **Test env** starts both dispatchers unconditionally with
  `adapter: Pigeon.Sandbox` — no credentials, and a test can preset
  `response: :unregistered` on a notification to exercise the dead-token path.

## Data model — `push_tokens` (both adapters)

Schema `GameServer.Push.PushToken` (`use GameServer.Schema`, UUIDv7), migration
in `apps/game_server_core/priv/repo/migrations/`:

| column | type | notes |
|--------|------|-------|
| `id` | uuid v7 | PK |
| `user_id` | uuid | `references(:users, on_delete: :delete_all)` |
| `token` | string | the FCM registration token or APNs device token |
| `platform` | string | `"android"` \| `"ios"` \| `"web"` |
| `provider` | string | `"fcm"` \| `"apns"` — **drives routing** (see Provider model). Client sets it at registration: iOS-native → `apns`, Firebase → `fcm` |
| `device_id` | string, null | dedupe key so re-registering a device rotates its token in place |
| `disabled_at` | utc_datetime, null | set when the provider reports the token dead — **soft-delete, never hard** (a token can come back) |
| `last_used_at` | utc_datetime, null | bumped on successful send |
| `metadata` | map | `app_version`, `locale`, … (size-capped) |
| timestamps | | |

- **Indexes:** `unique_index(:token)`; `unique_index([:user_id, :device_id], where: "device_id IS NOT NULL")` so a device upserts; partial `index([:user_id], where: "disabled_at IS NULL")` to serve the hot "this user's live devices" sweep and the dashboard counter at once. No `ALTER COLUMN`, no `DISTINCT ON` (CONTRIBUTING §Data model).
- **Caps** in `GameServer.Limits` (auto `LIMIT_*`, enforced in the changeset,
  listed in `@limit_categories`): `max_push_tokens_per_user` (20),
  `max_push_title` (255), `max_push_body` (4000), `max_push_data_size` (4096).
  The message caps are **bytes**, matching the providers' 4096-byte payload
  limits; the FCM adapter additionally size-checks the combined payload before
  sending, because FCM reports oversize as `INVALID_ARGUMENT` — the same code
  as a dead token — and only the pre-check keeps that from disabling a healthy
  device.

## `GameServer.Push` — the context

Token management (every `list_*` is paginated with a matching `count_*`,
CONTRIBUTING §Functionality):

```elixir
Push.register_token(user_id, %{"token" => ..., "platform" => "ios", "provider" => "apns", "device_id" => ...})
Push.unregister_token(user_id, token)
Push.list_tokens(user_id, page: 1, page_size: 25)   # + count_tokens/1
Push.list_all_tokens(filters, opts)                  # + count_all_tokens/1 (admin)
```

`register_token/2` **upserts** on `(user_id, device_id)` when a `device_id` is
given (rotates the token for that device), else on `token`; defaults `provider`
from the platform / configured default; enforces `max_push_tokens_per_user`;
re-enables a previously-disabled row. Any capacity check is a read-modify-write,
so it holds a `GameServer.Lock` (new advisory-lock namespace `:push_tokens` in
`GameServer.Repo.AdvisoryLock`), per CONTRIBUTING.

Delivery (server-authoritative — **no public send endpoint**, exposed through
hooks/admin only, CONTRIBUTING §Web):

```elixir
Push.send_to_user(user_id, %{title: ..., body: ..., data: %{...}}, opts)
Push.send_to_users([user_id], message, opts)          # reliable fan-out
```

- A `%GameServer.Push.Message{}` struct (`title`, `body`, `data`, `image`,
  `sound`, `badge`, `collapse_key`) is validated against the `Limits` caps
  before anything is enqueued.
- `send_to_user/3` runs the `before_push_send` pipeline (veto/rewrite), resolves
  the user's live tokens, then enqueues **`GameServer.Push.DeliveryWorker`**
  (`use Oban.Worker, queue: :push, max_attempts: 5`) — **one job per token**.
  FCM v1 and APNs are both one-request-per-token (Google discontinued the FCM
  batch endpoint in 2024), so batching would save nothing at the HTTP layer
  while breaking Oban's per-token retry/backoff. The worker resolves the
  token's provider, calls `deliver/2`, bumps `last_used_at` on `{:ok, _}`,
  calls `disable_token/1` on `{:invalid, _}`, returns `{:error, _}` on
  transient failures so Oban retries with backoff, `{:cancel, _}` on permanent
  ones, and fires `after_push_sent`.
- `send_to_users/3` past a small threshold (~100 recipients) does **not**
  resolve tokens inline: it enqueues one **`GameServer.Push.FanoutWorker`**
  job carrying the message + recipient spec. That worker keyset-paginates the
  recipients' live tokens and `Oban.insert_all`s delivery jobs in **chunks of
  500**, running the `before_push_send` pipeline per recipient as it goes. This
  bounds every transaction (SQLite is single-writer — one 200k-row insert
  would stall every other write), keeps the caller's request fast, and makes a
  huge broadcast resumable (the fan-out job itself retries; a `unique` key
  prevents double-broadcast).
- Add a **`push`** queue to the Oban config in `host_config.exs`
  (`queues: [..., push: 10]`), overridable at runtime via
  `GAMEND_PUSH_QUEUE_CONCURRENCY` (see Config).

## Performance & scale

The scale story in one line: **push can be slow without making anything else
slow** — it runs on its own bounded queue, behind its own supervisor, with
chunked writes, and degrades to `Log` rather than cascading.

**Isolation (can it crawl the server? — no).** Delivery runs on the dedicated
`push` Oban queue, so a 200k-token broadcast competes with other pushes, never
with `default`/`hooks`/`mailers` jobs, HTTP requests, or sockets. Queue
concurrency caps in-flight provider calls (backpressure — dispatcher mailboxes
can't balloon past it). The `before_push_send` pipeline runs inside the fan-out
worker, not on the caller's request path, so a slow plugin slows the push
queue, nothing else. Process failure is contained by `GameServer.Push.
Supervisor` + boot-time credential validation (see Dispatchers): worst case is
push routing to `Log` while the server runs on.

**Throughput & the queue knob.** Default `push: 10` ≈ 50–200 deliveries/sec
per node at typical provider RTTs — a 100k-device broadcast drains in tens of
minutes, which is fine for "patch notes" pushes. `GAMEND_PUSH_QUEUE_CONCURRENCY`
raises it: APNs/FCM speak HTTP/2 (Apple allows ~1000 concurrent streams per
connection), so one dispatcher per provider sustains hundreds of concurrent
pushes; OSS Oban has no rate limiter (that's Oban Pro), so concurrency **is**
the throttle, and provider `429`s classify as transient and back off through
retries. Queue depth is visible live on the existing `/admin/oban` dashboard.
If a single dispatcher ever measures as the bottleneck, Pigeon supports
running N dispatchers per provider — deferred until measured.

**Write amplification, bounded.** Fan-out is chunked (`insert_all` × 500, see
the context section) so no broadcast ever holds a long transaction — the thing
that would actually stall SQLite's single writer. Per-token job rows carry the
message payload; that's ~200 bytes typical, ≤ ~8.5 KB at the `Limits` caps,
and the already-configured `Oban.Plugins.Pruner` deletes completed jobs after
7 days, so job-table growth is bounded and self-cleaning.

**Caching — one deliberate cache, not three.** The hot read this feature adds
is `Notifications` asking "does this user have any live device?" on **every**
notification insert. That becomes `Push.user_has_live_tokens?/1`, cached in
`GameServer.Cache` (the notifications-cache pattern) and invalidated on
register/unregister/disable — so the common no-device case costs a cache hit,
not a query. Token *lists* are deliberately not cached: they're read once per
delivery inside the worker, served by the partial index
(`[:user_id] where disabled_at IS NULL`), and a cross-node cache would add
invalidation traffic for a point lookup. Provider auth caching (APNs JWT,
FCM OAuth) is Pigeon's/Goth's job — they mint and refresh internally.

**Steady-state hygiene.** Dead tokens are soft-disabled immediately on
provider signal (no growth in the hot partial index), and
`GameServer.Retention` hard-prunes the long tail — disabled rows and tokens
unused for `GAMEND_RETENTION_PUSH_TOKENS_DAYS` (default 270, Google's own staleness
guidance; `0` disables) — so `push_tokens` tracks the *live* device count, not
install history.

**Multi-node.** Queues and dispatchers run per node — N nodes = N× delivery
concurrency and N provider connections (both providers expect many
connections; no coordination needed). Oban leases jobs safely across nodes on
Postgres; the `:push_tokens` advisory lock is cluster-wide there too. SQLite
deployments are single-node by nature, where per-node reasoning collapses to
the single instance.

**Delivery semantics.** Oban gives at-least-once: a worker that crashes after
the provider accepted the push re-sends on retry. `collapse_key`/
`apns-collapse-id` makes the duplicate invisible on-device, so senders that
care set it; exactly-once bookkeeping is deliberately not built (its cost
exceeds the blast radius of a rare duplicate ping).

## Hooks (all six places, per CONTRIBUTING §Hooks)

Two callbacks — for each: `@callback` + `@optional_callbacks` in
`GameServer.Hooks`, add to `internal_hooks()` (RPC-blocked), no-op in
`GameServer.Hooks.Default`, mirror in the SDK (`@callback`,
`@optional_callbacks`, `__using__` default, **and `defoverridable`**), and
document on the Server-scripting page.

- **`before_push_send(user_id, message)`** — pipeline hook (add to
  `lifecycle_pipeline_hook?/2` + a `normalize_pipeline_args/3` veto clause).
  Lets a plugin drop a push (per-user opt-out, quiet hours, moderation) or
  rewrite it. **Never dispatched inside a lock/transaction** — resolved before
  the enqueue, results deferred and flushed after commit (`defer/1` pattern).
- **`after_push_sent(user_id, message, results)`** — observe per-token outcome.

Because delivery retries live behind Oban, any hook the worker invokes goes
through `GameServer.Jobs`/`HookWorker`, so it's auto-registered in
`ProtectedCallbacks` and blocked from client RPC (Phase 0 machinery).

## First consumer: `Notifications` → push

Mirrors "avatars are Storage's first consumer." After
`Notifications.send_notification/2` (and the admin/chat paths) commits and
broadcasts, it calls `Push.send_to_user/3` with the notification's title/content
so an **offline** friend still gets pinged. Kept decoupled and best-effort: the
call no-ops under the `Log` provider and when the recipient has no live tokens,
and it's queued after commit (never inside the insert), so a push failure can't
roll back a notification.

## Config (`host_config.exs` default + `host_runtime.exs` runtime)

```
GAMEND_PUSH_ADAPTER=log                 # optional override: force everything to Log (dev/staging)
                                 # unset → route per token to whichever provider is configured
GAMEND_PUSH_QUEUE_CONCURRENCY=10        # per-node concurrent deliveries (the throughput/throttle knob)
GAMEND_RETENTION_PUSH_TOKENS_DAYS=270   # prune disabled/unused tokens after N days (0 = keep forever)

# FCM (Android/Web, or iOS relay) — enabled when credentials are set
GAMEND_PUSH_FCM_CREDENTIALS=            # path to, or inline JSON of, the service-account key
GAMEND_PUSH_FCM_PROJECT_ID=             # optional — defaults to project_id from the credentials JSON

# APNs-direct (iOS) — enabled when the .p8 key + ids are set
APNS_KEY_ID=                     # 10-char key id of the APNs .p8 auth key
APNS_TEAM_ID=                    # Apple developer team id
APNS_PRIVATE_KEY=                # the .p8 contents (or a path to it)
APNS_TOPIC=                      # app bundle id, set as the notification topic
APNS_ENV=production|sandbox      # default production (Pigeon mode :prod / :dev)
```

`host_runtime.exs` translates these into the two dispatcher configs (+ Goth)
described under Dispatchers, mirroring the `GAMEND_STORAGE_ADAPTER` case block, and
rewrites the Oban `queues` entry when `GAMEND_PUSH_QUEUE_CONCURRENCY` is set
(`GameServer.Jobs.oban_config/0` reads app env, so runtime config wins). No
vars → no dispatchers → everything routes to `Log`.

## Web / API

- `POST /me/push_tokens` — register `{token, platform, provider?, device_id?}`.
- `GET  /me/push_tokens` — list my devices (paginated `meta` block).
- `DELETE /me/push_tokens/:id` — unregister one.
- Routes in `router/shared.ex` under the authenticated `/me` scope. **No**
  public send route — sending is server-authoritative. Listing is per-user
  (own devices), so no `LIST_*_ENABLED` global gate needed.
- OpenAPI schemas in the controller (`ids` `type: :string, format: :uuid`); SDKs
  regenerate from the spec in CI.

## Admin

- `admin_live/push.ex` — tokens table (names not UUIDs, paginated, filter by
  user/platform/provider, shows disabled), plus a **"send test push to user"**
  form.
- `/admin` stat card (registered devices, split by platform/provider) + route +
  nav link + an entry in `admin_pages_render_test`.
- `controllers/api/v1/admin/push_controller.ex` — parity for every UI action:
  list tokens, delete a token, send a push to a user.

## "Update everywhere we mention features" — concrete file list

- **`apps/game_server_core/mix.exs`** — `{:pigeon, "~> 2.0"}` (pulls `goth`,
  `joken`).
- **`host_supervision.ex`** (+ starter repo tree) — the conditional
  `GameServer.Push.Supervisor` child.
- **`retention.ex`** — `GAMEND_RETENTION_PUSH_TOKENS_DAYS` pruning wired into
  `prune_all/0` and the moduledoc's env-var list.
- **README.md** — Features: add **Push notifications**.
- **CHANGELOG.md** — `[added]` Push notifications (FCM + APNs); `[added]`
  Push-token storage.
- **.env.example** — all `PUSH_*` / `PUSH_FCM_*` / `APNS_*` vars +
  `LIMIT_MAX_PUSH_*`.
- **host_public_docs/** (registered in `host_public_docs.ex`): new **Push
  notifications** page (register flow, FCM service-account setup **and** APNs
  `.p8` key setup, sending from a hook); Data Schema page gains `push_tokens`.
- **api_spec.ex** — feature list + push-token endpoints.
- **SDK** — `sdk/lib/game_server/push.ex` + struct stubs
  `sdk/lib/game_server/push/{message,push_token}.ex`, add to `@sdk_modules`,
  `mix gen.sdk`, placeholder rules (`T | nil`, `{:ok, T}`); hooks mirrored.
- **runtime_introspection.ex** — Push section: token counts (total, per
  platform, per provider, disabled) + `push` queue stats.
- **.github/copilot-instructions.md** — mention push in the feature overview.
- **i18n** — `gettext.extract` + `merge`, translate all 30 locales, clear
  fuzzies.
- **mix demo.seed** — seed sample push tokens (under the `Log` provider) so the
  admin page shows devices at volume.

## Deferred / rejected, with reasons

- **Hand-rolled providers (req/Finch/jose, no library): no.** The repo has the
  raw parts (HTTP/2 via `finch`/`mint`, ES256 via `jose`, retries via Oban),
  but the value of the library is the provider edge-cases — APNs JWT refresh on
  `ExpiredProviderToken`, connection pings/GOAWAY, response taxonomy — which
  are exactly the fiddly, rarely-exercised paths. Pigeon 2 runs on Mint (no
  second HTTP/2 stack) and is the maintained standard; the `Provider`
  behaviour keeps it swappable if it ever stalls.
- **Rich push (actions / silent / Live Activities) beyond the basic fields:
  defer.** Ship `title`/`body`/`data`/`image`/`sound`/`badge`/`collapse_key`.
  APNs-direct leaves the door open to Live Activities later (it's an
  APNs-native push type), but the client-render side waits for the Godot client
  to demonstrate demand.
- **Per-user notification-preference matrix: defer.** The `before_push_send`
  veto hook already lets a plugin implement opt-out/quiet-hours; a first-class
  preferences table can generalize that later without changing this contract.
- **Dispatcher pools / rate limiting: defer.** One dispatcher per provider per
  node multiplexes hundreds of concurrent HTTP/2 streams — measure before
  pooling (Pigeon supports N dispatchers when needed). A real rate limiter is
  Oban Pro's Smart Engine; on OSS, `GAMEND_PUSH_QUEUE_CONCURRENCY` is the throttle
  and provider `429`s back off through retry.
- **Certificate-based APNs auth: no.** Pigeon supports `.p12` certs, but token
  auth (`.p8` ES256) is the modern path — one key for all apps, no yearly cert
  rotation. Not exposed in config.

## Definition of done (CONTRIBUTING)

- [x] `push_tokens` migration applies on SQLite **and** `GAMEND_DB_ADAPTER=postgres`.
- [x] `GameServer.Push` context: paginated `list_*`/`count_*`, `Limits` caps in
      the changeset, capacity write-modify-write under a `:push_tokens` lock,
      dead-token soft-disable, per-token provider routing.
- [x] `FCM` + `APNs` + `Log` providers behind the behaviour, the Pigeon ones as
      thin wrappers over `Pigeon.push/2`; Goth + dispatchers under
      `GameServer.Push.Supervisor`, conditionally started; zero-config boot
      still works; garbage credentials boot to `Log` with one loud error
      instead of crash-looping.
- [x] `DeliveryWorker` on the new `push` Oban queue, one job per token: retries
      transient, cancels permanent, disables invalid, fires `after_push_sent`;
      `GAMEND_PUSH_QUEUE_CONCURRENCY` respected.
- [x] `FanoutWorker` chunks large `send_to_users/3` (chunked resolution +
      `insert_all` × 500, unique-keyed against double broadcast); inline path
      below the threshold.
- [x] `user_has_live_tokens?/1` cached with invalidation on
      register/unregister/disable; `Notifications` uses it for the no-device
      fast path.
- [x] `GAMEND_RETENTION_PUSH_TOKENS_DAYS` pruning in `GameServer.Retention`.
- [x] Hooks `before_push_send` / `after_push_sent` in all six places, RPC-blocked,
      SDK-mirrored; `Notifications` calls `Push.send_to_user/3` after commit.
- [x] Admin page + `/admin` card + route + nav + `admin_pages_render_test`;
      admin API parity (list / delete / send).
- [x] Docs pages, `.env.example`, `CHANGELOG`, README, `api_spec.ex`.
- [x] Tests: context + controller + admin + LiveView, on both DB adapters. Boot
      and actually register a token and run a delivery job end-to-end (Log
      provider); stub providers through the worker prove dead-token responses
      disable the token and transient errors retry; response classification
      unit-tested for both providers; Sandbox-backed dispatcher exercised end
      to end.
- [x] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
