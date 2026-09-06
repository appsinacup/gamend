---
icon: hero-wrench-screwdriver
---

# Admin Console

Every operational surface of the server is a LiveView under `/admin`, gated to admin-level accounts. The console is not a separate service: it runs in the same process as the game, reads the same contexts the API reads, and most of what it can do is mirrored as an admin HTTP API for scripting.

## Access

A user with `is_admin` set can open the console; everyone else gets redirected. The gate is enforced twice, on the HTTP request and again on the LiveView socket, so a stale page cannot keep operating after the flag is removed. Admins edit the flag itself on the Users page, which is also where a locked-out colleague's sessions get revoked.

## Players & sessions

| Page | What it does |
|---|---|
| [/admin/users](/admin/users) | Search, sort and edit every account: display name, activation, admin flag, metadata, linked OAuth providers. Per-user token revocation, revoke-all-sessions, delete and bulk delete. |
| [/admin/sessions](/admin/sessions) | Active browser session tokens with context and age. Deleting one signs that browser out; bulk delete signs out many at once. |

## Social

| Page | What it does |
|---|---|
| [/admin/lobbies](/admin/lobbies) | Browse, create, edit and delete lobbies; add or kick members; cancel a stuck ready check. `/admin/lobbies/live` is the same realtime lobby browser players see. |
| [/admin/parties](/admin/parties) | The same operations for parties: create, edit, disband, add and kick members. |
| [/admin/groups](/admin/groups) | Group CRUD plus member management — promote, demote and kick from the members drawer. |
| [/admin/blacklist](/admin/blacklist) | Every block in the system, filterable by a user on either side, with force-unblock for support cases. |
| [/admin/friends](/admin/friends) | Friendships and pending requests, with filters and force-remove for relationships stuck in a bad state. |

## Competition

| Page | What it does |
|---|---|
| [/admin/leaderboards](/admin/leaderboards) | Leaderboard CRUD, ending a board, starting a new season from an old one — and full record surgery: add, edit and delete individual scores. |
| [/admin/tournaments](/admin/tournaments) | Tournament CRUD and the force controls: reopen or close registration, force the draw, resolve or finish, cancel. Brackets are browsable per edition. |
| [/admin/matchmaking](/admin/matchmaking) | Live tickets with cancel, plus a "sweep now" that runs the matcher immediately instead of waiting for the next tick. |
| [/admin/quests](/admin/quests) | Quest definition CRUD and per-player intervention: grant a quest, force-complete, force-claim, reset progress, browse everyone's progress. |

## Communication

| Page | What it does |
|---|---|
| [/admin/chat](/admin/chat) | Every message, filterable, with single and bulk delete. |
| [/admin/chat/reports](/admin/chat/reports) | The player-report review queue — review a report and act on it in place. |
| [/admin/chat/mutes](/admin/chat/mutes) | Mute or unmute a player, with editable reason and duration. |
| [/admin/chat/filter](/admin/chat/filter) | The word blocklist: add and edit words, import the bundled per-language lists, and test a message against the live filter. |
| [/admin/notifications](/admin/notifications) | Browse, create and delete in-app notifications. |
| [/admin/push](/admin/push) | Registered device tokens, with delete for stale ones and a send form for test pushes. |

## Money

| Page | What it does |
|---|---|
| [/admin/payments](/admin/payments) | Products and per-provider product mappings, purchase and entitlement listings, and a reconcile action for a Stripe purchase whose webhook was missed. |
| [/admin/economy](/admin/economy) | Wallets, item stacks and the ledger, searchable by username as well as user id, with grant and spend forms for currency and items. |

## Data

| Page | What it does |
|---|---|
| [/admin/kv](/admin/kv) | The key-value store: filter, create, edit, delete and bulk delete entries. |
| [/admin/storage](/admin/storage) | Object storage usage, a paginated object list with preview and delete, and a direct upload — the same view whether the backend is local disk or S3/R2. |
| [/admin/lobby_snapshots](/admin/lobby_snapshots) | Durable per-run lobby snapshots (when `GAMEND_LOBBY_SNAPSHOTS_ENABLED` is on), with their event timelines and a flagged-only toggle. |
| [/admin/retention](/admin/retention) | The configured retention windows with per-table row counts, and a manual prune that runs the sweep immediately instead of waiting for the schedule. |

## System

Two pages that look similar and are deliberately not:

- [/admin/config](/admin/config) is the *operable* one — configuration status with masked provider variables, hook invocation with prefilled arguments, plugin reload and bundle build, and a test-email button.
- [/admin/settings](/admin/settings) is *read-only by design*: every declared setting with its effective value and where that value came from. Settings resolve once at boot, so an editable field here would promise a change it could not deliver.

| Page | What it does |
|---|---|
| [/admin/runtime](/admin/runtime) | Read-only introspection of what the code actually loaded: hooks, env vars, protobuf messages, channels and realtime events, an ER diagram of the data model, plugins and their RPCs, scheduled jobs, advisory locks, migration status. |
| [/admin/system](/admin/system) | Node health: uptime, OTP release, scheduler utilisation, a BEAM memory breakdown, ETS tables and cluster size. |
| [/admin/connections](/admin/connections) | Live connection counts — WebSockets, LiveViews, WebRTC peers — per cluster node, with a filterable per-connection list. |
| [/admin/rate_limiting](/admin/rate_limiting) | Rate-limiter status across the HTTP, auth, WebSocket and WebRTC buckets, plus IP bans: ban with an optional TTL, unban, and the recent ban log. See the [Security guide](/docs/security). |
| [/admin/geo](/admin/geo) | Traffic by country over 1h/24h/7d/all windows, with the active source shown (MaxMind database or the CF-IPCountry header) and a counter reset. |
| [/admin/logs](/admin/logs) | The in-memory log ring buffer, filterable by level, module, text, source (server vs client) and session — including uploaded client-log sessions with per-session timelines and flagging. |
| [/admin/translations](/admin/translations) | Locale completeness and every translatable string, filterable by domain and status. |
| [/admin/analytics](/admin/analytics) | DAU / WAU / MAU, new users, D1 / D7 / D30 cohort retention and payer conversion over the last 30 or 90 days. |

## Mounted alongside

Four routes live next to the console rather than in it:

- **[/admin/dashboard](/admin/dashboard)** — Phoenix LiveDashboard, wired to the server's telemetry. Admin-gated.
- **[/admin/oban](/admin/oban)** — the Oban Web job dashboard, for watching and retrying background jobs. Admin-gated on both the request and the socket.
- **/metrics** — the Prometheus endpoint, gated by loopback or a bearer token rather than an admin session, because a scraper has no cookie. See [Metrics & Observability](/docs/observability).
- **[/api/docs](/api/docs)** — Swagger UI over the OpenAPI spec, behind `GAMEND_FEATURES_OPENAPI`. The admin HTTP mirrors of the console actions are documented there too.

## Reference

- **Admin HTTP API:** [/api/docs](/api/docs) — the scripting mirror of the console actions, under `/api/v1/admin`.
- **Settings:** the [Settings guide](/docs/settings) lists every `GAMEND_*` variable the pages above read.
- **Security:** the [Security & Rate Limiting guide](/docs/security) covers the gates in front of all of this.
