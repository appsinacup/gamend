# Load testing — a benchmark suite, a capacity test, and a hardware/DB matrix on Fly

> **Results so far:** [stress/SUMMARY.md](../../stress/SUMMARY.md) is the one-page
> version; [stress/baselines/2026-08-19-macbook-air-m1.md](../../stress/baselines/2026-08-19-macbook-air-m1.md)
> has every number. This document is the plan and the open questions.

Plan for the second round of stress testing (the first is
[blog/2025-12-14-gamend-stress-test.md](../../blog/2025-12-14-gamend-stress-test.md):
one flow — device login + 10× `/me` — on a single `shared-cpu-4x` SQLite box,
which found the OOM at 256 MB and the DB-queue 5xx cascade, and led to the
Nebulex cache). This round answers three questions with three tools, over a
matrix of machine sizes with both adapters.

Goal:

1. **Per-feature numbers** — what each operation costs, and SQLite vs Postgres
   per operation *type* (cached read / plain write / locked write / broadcast).
   Reusable as a regression benchmark: "did this commit make lobby create 2×
   slower?"
2. **Capacity, and what more money buys** — concurrent players at an SLO for
   each `DB × machine` cell, with the monthly price next to it.
3. **Where it breaks next** — the bottlenecks after the cache: bcrypt,
   single-writer SQLite, broadcast fan-out, memory per socket.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Tool | **k6**, extend `stress/`. Not the JS SDK. | Already in use; HTTP + WebSocket + thresholds + JSON summaries; ~1–3 MB per VU so one small machine drives 5k VUs. The SDK (superagent + phoenix.js) doesn't run inside k6, and a Node harness means writing our own scheduler and histograms. Phoenix's channel wire protocol is 5 fields — a 60-line helper reproduces it. |
| Individual vs. end-to-end | **Both, layered.** Isolated per-feature scenarios first (the benchmark), then one weighted "player session" journey built from the same helpers (the capacity test). | Isolated scenarios give comparable per-endpoint numbers you can act on. The journey gives the one headline number per cell. |
| Auth in the test | **Device login** everywhere (one fresh device user per VU / per socket — realistic and sidesteps every per-user limit). **Email+password login** as one isolated scenario against seeded users. No OAuth, no browser registration. | OAuth measures Google. Registration is LiveView + mail. Seeding email users needs no mail at all — see below. |
| Hooks | Yes, two ways: (a) `hooks_rpc.js` stresses the plugin path itself (noop / memory / KV read / KV locked write); (b) hooks are how the harness triggers server-side writes players can't do over HTTP (quest events, scores, wallet credits, seeding). Those appear inside the *regular player* scenarios, not only in the RPC one. | Player-facing HTTP has no KV write, no quest progress, no score submit — those are game-server (plugin) operations by design, so a realistic player mix must include hook calls. |
| Bench plugin | **`modules/plugins_examples/stress_hook/`** — a normal example plugin next to `example_hook`, no gate. The `bench_*` RPCs move out of `example_hook` into it. | Plugins are per-deployment: a real game points `GAMEND_CONTENT_PLUGINS_DIR` at its own directory (gamend_polyglot does), so the examples never load in someone's production. Being a plain plugin means the published image can be the bench target with no special build. |
| Postgres placement | **Separate machine, same region.** | Fly runs one process per machine; separate is also the scaling topology. |
| Load generator | A **k6 machine on Fly, same region**, hitting `gamend-bench.internal:4000` (bypasses fly-proxy). One confirmation run per DB through the public edge. | Removes internet jitter and proxy limits from the app measurement; the public run shows what a player sees. |
| Server metrics | Fly's built-in Prometheus + Grafana (`[metrics]` in fly.toml → fly-metrics.net) scraping the existing PromEx `/metrics`. | Zero infra; BEAM/Ecto/Phoenix/cache metrics next to VM CPU/mem/net. |
| Results | k6 `handleSummary` → one JSON per (cell, script) in `stress/results/` (gitignored). `report.mjs` renders a folder as a table, `--diff`s two runs, and writes both a full Markdown report and a self-contained HTML page (`--md` / `--page`, charts inline, no CDN); the summaries that go in the blog are committed under `stress/baselines/`. | Comparable across runs and commits, no database — and the page is the shareable artifact a post can link. |

## Email login without email

No mailer, no confirmation token: `SessionController.create` only checks
`Accounts.user_activated?/1`, and `require_activation` defaults to `false`.
Email *confirmation* is a separate flag the API login path does not read.

Two calls, though, not one — this bit was wrong in the first draft and the
harness found it. `Accounts.register_user/1` composes only the email and
username changesets (this product registers by magic link and sets a password
afterwards), so a password handed to it is dropped silently and the row lands
with a NULL hash that answers 401 forever. `stress_seed_users/3` follows the
insert with `Accounts.update_user_password/2`. Worth knowing because the
failure is invisible: `User.valid_password?/2` falls back to
`Bcrypt.no_user_verify/0`, so a passwordless user costs the *same* bcrypt time
as a real one and the benchmark looks healthy while measuring the reject path.

**Can it be faster?** bcrypt is the cost by construction: `bcrypt_elixir`
defaults to 12 rounds ≈ 250 ms of one core per verify (on dirty schedulers, so
it eats cores but doesn't stall the VM). Levers, in order:

1. **It's a login-rate ceiling, not a CCU ceiling.** Refresh tokens
   (`POST /refresh`) are cheap; a player pays bcrypt once per session, not per
   request. The scenario reports *logins/s*; the journey logs in once and
   refreshes, like a real client.
2. **Fewer rounds.** `config :bcrypt_elixir, :log_rounds` — 10 rounds is 4×
   cheaper and still ≈60 ms. Not a setting today; worth adding as
   `GAMEND_AUTH_BCRYPT_LOG_ROUNDS` only if the number turns out to matter (a
   login storm after a restart is the case that would justify it).
3. The rate limiter's `auth_limit` is what actually protects prod from a bcrypt
   flood; it stays off in the bench.

Not levers: caching a verify (that would cache passwords), argon2 (same cost
class by design).

## Harness layout

Everything stays under `stress/` (results dir already in `.gitignore`).

```
stress/
  README.md                 local runs, Fly runs, reading results
  lib/
    config.js               env → BASE_URL, VUS, DURATION, SLO thresholds
    auth.js                 device login (fresh device per VU), email login, per-VU token cache, refresh
    api.js                  thin wrappers, one per endpoint used (mirror api paths, not the SDK)
    phx.js                  Phoenix channel v2 over k6/ws: connect(token), join(topic), push, waitFor(event), heartbeat
    hooks.js                callHook(name, args) over HTTP; over WS via phx.js
    checks.js               shared consistency checks (see "Correctness inside the load test")
  scenarios/                isolated per-feature benchmarks (Tier 1)
    auth_device.js          POST /login/device (new device each iter)          write
    auth_email.js           POST /login (seeded users)                          cpu (bcrypt)
    auth_refresh.js         POST /refresh                                       cheap
    me.js                   GET /me                                             cached read
    profile_write.js        PATCH /me/display_name → GET /me must reflect it   write + read-your-write
    kv_read.js              GET /kv/:key                                        cached read
    hooks_rpc.js            noop / memory / kv_read / kv_write_locked           plugin path
    lobbies_http.js         create → 3 join → state transition → leave/disband  write-heavy
    lobby_ws.js             same, with lobby:<id> joined; event delivery latency
    chat.js                 POST /chat in a lobby; own message round-trip on channel = broadcast latency
    matchmaking.js          tickets in pairs on user channel; time-to-match_found; leave lobby
    groups.js               create / join / members / group chat
    quests.js               hook stress_quest_event → GET /me/quests → claim
    leaderboards.js         hook stress_submit_score → records / around / me
    economy.js              hook stress_credit → GET /me/wallet, /me/inventory
    friends.js              request / accept / list
    notifications.js        list, mark read
    ws_join_idle.js         connect, join user:*, dwell, close — the socket building block
    web_pages.js            GET / , /groups, /users/log_in, a blog post (dead renders only)
  journeys/                 mixed, weighted (Tier 2 + 3)
    player_session.js       login → me → quests → 30% matchmaking / 50% lobby+chat / 20% groups → wallet; ramping arrival rate
    ws_idle.js              N sockets, one device user each, joined to user:*, heartbeat only — memory & connection ceiling
    ws_storm.js             connect N sockets as fast as possible, hold, drop them all at once, reconnect — connect/s and recovery
    lobbies_storm.js        N subscribers on `lobbies` + M writers — global fan-out cost
    soak.js                 player_session at 70% of measured capacity for 30 min
  suite.sh                  runs every scenarios/*.js sequentially at fixed VUs, one JSON each
  sweep.sh                  one scenario across a VU ladder — the saturation curve
  report.mjs                results/*.json → table, --md/--page reports, --diff a b
  page.mjs                  the Markdown and HTML report templates, charts included
  fly/
    fly.bench.toml          the target app
    fly.k6.toml + Dockerfile  the generator machine (grafana/k6 + this dir baked in)
    matrix.sh               for each cell: scale target, wait for /health, run suite + journey + ws, capture logs, fetch results
  results/                  gitignored
  baselines/                committed: one summary per (cell, commit) that was published

modules/plugins_examples/stress_hook/   the bench plugin (normal example plugin)
```

`benchmark.js` and `device_login.js` are absorbed (`hooks_rpc.js`,
`auth_device.js`); `run.sh` becomes `suite.sh` + `matrix.sh`.

### `phx.js` in one paragraph

Connect to `ws(s)://host/socket/websocket?token=<jwt>&vsn=2.0.0` with `k6/ws`.
Frames are JSON arrays `[join_ref, ref, topic, event, payload]`; heartbeat is
`[null, ref, "phoenix", "heartbeat", {}]` every 30 s (server timeout is 5 min).
`join(topic)` sends `phx_join`, resolves on the matching `phx_reply`.
`waitFor(topic, event, pred, timeoutMs)` records a Trend of arrival latency.
Optional `format=protobuf` (server→client only) to include encode cost — k6
receives binary frames without decoding them, which is fine for server-side
cost. Client→server stays JSON either way.

## Running locally

Yes — `k6` is installed and every script takes `BASE_URL`. Two modes:

- **Iterating on scripts / correctness:** `docker compose up` (SQLite) or
  `docker compose -f docker-compose.multi.yml up --scale app=1` (Postgres), then
  `BASE_URL=http://localhost:4000 k6 run stress/scenarios/me.js`. Prod config;
  the compose env needs `GAMEND_RATELIMIT_ENABLED=false` and the plugins dir
  pointed at `modules/plugins_examples`.
- **Numbers on your own machine:** run the server natively, not in Docker
  Desktop (its VM and vpnkit add their own overhead on macOS). `MIX_ENV=prod
  mix phx.server` with the same env; dev mode has code reloading and debug logs.

Local numbers are **relative only**: k6 and the server share the same cores, so
keep VUs modest (≤ 500) and use them to compare *before/after a change on the
same laptop*, never against the Fly cells. `report.mjs --diff` is built for
exactly that loop.

## The bench target: config that must differ from prod

A **separate Fly app** (`gamend-bench`), never `game-server-uro`. Runs the
published image (`ghcr.io/appsinacup/gamend:latest`, or `:latest-postgres` —
the adapter is compile-time, so it is two images, not a flag). To benchmark a
branch instead, `fly deploy` the same app from source with
`--build-arg GAMEND_DB_ADAPTER=…`.

| Setting | Value | Why |
|---|---|---|
| `GAMEND_CONTENT_PLUGINS_DIR` | `modules/plugins_examples` | Loads `stress_hook` (the image's default already points here). |
| `GAMEND_RATELIMIT_ENABLED` | `false` | Buckets are per **IP**: 10 auth/min and 240 req/min. One generator = one IP. Do exactly one run with it *on* and limits set high, to see what the plug itself costs. |
| `GAMEND_AUTH_DEVICE_AUTH_ENABLED` | `true` | Default auth path. |
| `GAMEND_FEATURES_LIST_LOBBIES`, `GAMEND_FEATURES_LIST_GROUPS` | `true` | Public list routes **and** the `lobbies`/`groups` channels are behind `FeatureGate`. On by default; set them explicitly so a host that turned them off still runs the journey and `lobbies_storm`, which need them. |
| `GAMEND_OBSERVABILITY_METRICS_TOKEN` | unset | `/metrics` allows private-network callers when unset — Fly's scraper. |
| fly.toml `[metrics] port=4000 path="/metrics"` | — | Fly-hosted Grafana. |
| fly.toml `[http_service.concurrency]` | `type="connections"`, `hard_limit=50000` | Today's 5000 caps a WebSocket test at the proxy on the public-edge run. |
| fly.toml `auto_stop_machines=false`, `min=max=1` | — | Don't measure a cold start. |
| `GAMEND_DB_SQLITE_CACHE_SIZE_KB` | check | Default 200 MB **per connection**; pool of 5 → up to 1 GB page cache. On the 1 vCPU cell that alone may be the OOM. |
| `GAMEND_DB_POOL_SIZE` | sweep on Postgres | 10 default; try 20/40 on the 8- and 16-vCPU cells. Leave SQLite at 5 (single writer). |
| Fresh DB per cell | — | Delete the volume / drop the DB between cells so table sizes don't drift into the comparison. Within a cell, runs accumulate (fine — 100k users is realistic). |

Leave `GAMEND_LIMITS_MAX_SOCKETS_PER_USER` at its default (20). Every socket is
its own device user, which is both more realistic and how the limit is meant to
be respected — so the limit never actually trips, but the *check* still runs on
every connect. It is counted from a per-user registry key, so `0` and `20`
cost the same; run cell B once with `0` to confirm that on the machine rather
than on the reasoning.

Two new knobs, both defaulting to today's behaviour, both worth one run each on
cell B (and on H, where they should matter most):

| Setting | Default | Try |
|---|---|---|
| `GAMEND_REALTIME_PUBSUB_POOL_SIZE` | 1 | `System.schedulers_online()` — spreads PubSub dispatch across schedulers |
| `GAMEND_REALTIME_PRESENCE_POOL_SIZE` | 1 | 8 — spreads presence replication; connected users are already bucketed across 64 topics so the pool has something to spread |

Both shard by topic and both must match on every node of a cluster, so they are
a full-restart change, not a rolling one. That is why they default to 1 rather
than to something scheduler-sized: single-node deployments are unaffected, and
the horizontal round is where the number is worth having.

Postgres target: `fly postgres create --region ams --vm-size performance-2x`
(kept **constant** across app sizes so the DB is not the variable),
`GAMEND_DB_URL` secret pointing at the `.flycast` address,
`GAMEND_DB_IPV6=true` (Fly private network is v6-only).

## The generator

`stress/fly/Dockerfile`: `FROM grafana/k6`, copy `stress/` to `/scripts`,
entrypoint `sleep infinity`. Deployed as app `gamend-k6`, no HTTP service, same
region, `performance-2x` (4 GB drives 5k HTTP VUs; `-4x` for the 20k-socket
`ws_idle` run). Runs launch with
`fly ssh console -a gamend-k6 -C "k6 run -e BASE_URL=http://gamend-bench.internal:4000 … /scripts/suite.sh"`
(streams stdout back); summaries land in `/results/` and come back with
`fly ssh sftp get`. `matrix.sh` wraps that loop.

## Matrix

Memory pinned to 2 GB on the shared sizes so CPU is the only variable there
(round one already showed 256 MB OOMs). The `≈ $/mo` column is Fly list price
for the app machine (verify with `fly platform vm-sizes` — machines bill per
second, so the whole matrix costs a few dollars to run).

| # | DB | App VM | ≈ $/mo | Answers |
|---|---|---|---|---|
| A | SQLite | `shared-cpu-1x` 2 GB | ~12 | the cheap floor |
| B | SQLite | `shared-cpu-4x` 2 GB | ~13 | today's prod |
| C | SQLite | `performance-4x` 8 GB | ~124 | shared vs dedicated at 4 vCPU |
| D | SQLite | `performance-8x` 16 GB | ~248 | does SQLite scale past 4 cores at all (single writer) |
| E | Postgres | `shared-cpu-4x` 2 GB | ~13 + pg | vs B — pure DB delta at prod size |
| F | Postgres | `performance-4x` 8 GB | ~124 + pg | vs C |
| G | Postgres | `performance-8x` 16 GB | ~248 + pg | vs D — vertical scaling |
| H | Postgres | `performance-16x` 32 GB | ~496 + pg | is the BEAM or the DB saturating; with pool 10/20/40 |
| — | Postgres | `performance-4x` app, pg `shared-cpu-1x` | — | one run: when does the DB box become the bottleneck |

Per cell, in order (≈40 min): `suite.sh` (all isolated scenarios, fixed VUs,
~15 min) → `player_session.js` ramp to SLO breach (~10 min) → `ws_idle.js`
(~5 min) → `ws_storm.js` (~5 min) → `lobbies_storm.js` (~5 min). `soak.js`
(30 min) only on B and F. One `player_session` per DB through the public URL.

Later, not this matrix: **horizontal** — 2× app `performance-4x` + Postgres +
Upstash Redis (`GAMEND_CACHE_MODE=multi`, `GAMEND_RATELIMIT_BACKEND=redis`,
`GAMEND_CLUSTER_DNS_QUERY` for `dns_cluster`). Compare 2×4 against 1×8 (cell
G). That is also where the staleness checks below earn their keep.

## The connect storm

`ws_idle.js` answers "how many sockets fit". `ws_storm.js` answers the question
that actually bounds a live game: **how fast can sockets be established, and
what happens when they all come back at once.** A deploy, a fly-proxy restart
and a mobile carrier handover all produce the same shape — every client
reconnecting inside a few seconds — and it is a different cost from holding
them.

Shape: ramp to N sockets as fast as the generator can open them (report
**connects/s** and p95 connect+join latency, not just the plateau), hold 60 s,
close all N at once, then reconnect all N. The metrics that matter are
connects/s, time-to-full-recovery, and whether the app 5xxes or the DB queue
backs up during the reconnect.

This is where the join path is measured rather than the socket count. Per
connection, before this round's fixes, the server did: a JWT verify, a scan of
every socket on the node for the per-user connection limit, a Presence track, an
uncached `Repo.get` on `users`, a friends query, a notifications query, and five
PubSub subscribes — with the disconnect side listing every tracked user in the
cluster to answer "was that their last socket?". Both scans were O(all
connections), which made a mass reconnect quadratic.

Those are fixed (see "Fixes that landed before this round"), so `ws_storm.js`
measures the fixed path — and the pre-fix commit is the natural `--diff`
baseline for the blog post.

## Estimates — written down before running

Guesses to be contradicted, extrapolated from round one (`shared-cpu-4x` 1 GB
SQLite: ~3000 rps of login + cached `/me` at 4000 VUs, but p99 15 s — call it
~1500 rps inside an SLO).

**Three different numbers get called "CCU" and the blog post must not mix
them**, so they are three columns:

- **Sockets held** — open, joined to `user:*`, heartbeating, no other traffic
  (`ws_idle.js`). This is the number other game servers advertise.
- **Connects/s** — how fast those sockets can be established (`ws_storm.js`).
- **Players at SLO** — sockets *plus* ~0.2 req/s of real traffic each, inside
  HTTP p95 < 300 ms and errors < 1 % (`player_session.js`). The honest capacity
  number, and the smallest of the three.

Nakama's published per-node benchmark is in the last column as a reference
point, because it is the comparison every reader will make. Note what it is
measuring: its "CCU" is sockets held, and its auth figure is custom-ID auth with
no password hash — so it belongs next to `auth_device.js`, never next to
`auth_email.js` (which is bcrypt-12 by construction and would cost the same in
any language).

| # | Cached reads (rps @ p95<300 ms) | Writes/s | Email logins/s | Sockets held | Connects/s | **Players at SLO** |
|---|---|---|---|---|---|---|
| A | 300–600 | 200–500 | 3–4 | 20–35k | 200–500 | 1–2k |
| B | 1.2–2k | 300–800 | 10–15 | 20–35k | 500–1.5k | 4–8k |
| C | 3–5k | 300–800 | 16 | 80k+ | 1–3k | 8–12k |
| D | 5–8k | 300–800 (plateau) | 32 | 150k+ | 2–5k | 10–15k |
| E | 1.2–2k | 1–2k | 10–15 | 20–35k | 500–1.5k | 5–9k |
| F | 3–5k | 4–8k | 16 | 80k+ | 1–3k | 12–20k |
| G | 5–8k | 8–15k | 32 | 150k+ | 2–5k | 20–35k |
| H | 8–12k | 10–20k | 64 | 300k+ | 3–8k | 30–50k |

Reference — [Nakama's own benchmarks](https://heroiclabs.com/docs/nakama/getting-started/benchmarks/),
per node, for the "sockets held" and device-auth columns:

| Nakama config | Sockets held | Auth/s (no bcrypt) | RPC/s |
|---|---|---|---|
| 1 node, 1 CPU / 3 GB | ~20,277 | 531 | 705 (Go), 707 (Lua) |
| 2 nodes, 1 CPU / 3 GB each | ~29,550 | 766 | — |
| 2 nodes, 2 CPU / 6 GB each | ~35,723 | 934 | 825 (Go) |

The widely-quoted "Nakama does 2M CCU" is a *cluster* result (Code Wizards on
Heroic Cloud, AWS EKS + RDS), not a per-node one; the per-node number is the
20k above. The same distinction applies to us: Phoenix's 2M-connection run was
2M *bare* channels on one 40-core / 128 GB box, i.e. a 64 KB/connection RAM
budget with no application work on join at all. Neither number is a claim about
a feature-complete game server, and this table should be the only thing the
blog post claims.

Three shapes to look for: SQLite's write column going flat from C to D while
reads keep climbing (that is the "when to move to Postgres" line); players-at-SLO
on the shared cells being CPU-bound long before RAM-bound; and connects/s
scaling with cores rather than with RAM.

**Memory per socket** is derived, not a new metric — no server code needed.
`report.mjs` computes `(BEAM memory at plateau − BEAM memory at idle) / sockets
opened`, taking the memory from the PromEx BEAM metrics already scraped and the
socket count from k6's own VU count during `ws_idle.js`. Guess: 50–100 KB
(transport process + `user:*` channel + Presence entry + two Registry entries +
five PubSub subscriptions). Vary friend count across `ws_idle` runs — the
`ChannelUpdates` friend memo lives on the socket's heap for its whole life, so
per-socket memory scales with how many friends the account has, and that is
worth a row of its own.

Note: connection counts per type live in `GamendWeb.ConnectionTracker` and the
admin Runtime page, not in Prometheus. Deriving from k6 avoids adding a PromEx
plugin just for this round; if the derived number turns out to be interesting,
exporting the tracker counts is the follow-up.

## Fixes that landed before this round

Found by reading the connect path rather than by measuring it — two of them are
unambiguous algorithmic bugs, so they were fixed rather than benchmarked. The
pre-fix commit is the `report.mjs --diff` baseline for the blog post.

| Fix | Was | Now |
|---|---|---|
| Per-user socket limit ([`UserSocket`](../../apps/gamend_web/lib/gamend_web/channels/user_socket.ex)) | `Registry.lookup(:ws_socket)` returned every socket on the node and counted it, on every connect — O(all connections), so a reconnect storm was quadratic | counted from a `{:ws_socket, user_id}` registry key, like the user-channel count already was |
| Last-socket check ([`Gamend.Presence`](../../apps/gamend_core/lib/gamend/presence.ex)) | `list("users")` built a map of every tracked user in the cluster to read one key, on every disconnect | `get_by_key/2` |
| Presence topic | one global `"users"` topic, so `Phoenix.Tracker` pinned every diff to one shard no matter the pool size | bucketed over 64 topics (compile-time constant — every node must bucket identically), with `presence_pool_size` now configurable |
| PubSub | started with the default `pool_size: 1` | `GAMEND_REALTIME_PUBSUB_POOL_SIZE`, still defaulting to 1 |
| `users.is_online` write | one uncached `Repo.get` per socket join, plus one transaction per transition — N distinct players connecting at once is N transactions serialized behind SQLite's single writer | cached read answers the no-op case (reconnects, extra tabs) with no query at all; real transitions are coalesced by `Gamend.Accounts.PresenceWriter` into one SELECT + one UPDATE per window (`flush_ms`, default 200, `0` writes through as before and is what tests run) |
| Global lobby fan-out ([`Gamend.Lobbies`](../../apps/gamend_core/lib/gamend/lobbies.ex)) | every `lobbies` subscriber serialized the lobby independently, and an unloaded `:host` sent each of them to `Accounts.get_user/1` for the display name — 1000 subscribers meant 1000 user reads per event | the host is resolved once at the broadcast site |

Left alone deliberately, in both cases because the cost is not yet demonstrated:

**The initial join payloads.** `UserChannel`'s `after_join` still runs a friends
query (`page_size: 1000`) and a notifications query per socket, unconditionally.
Making them opt-out in the join payload was tried and reverted: a per-client
on/off switch complicates every SDK and every client for a saving nobody has
measured yet. The friend memo also stays on the socket's heap for its whole
life, so per-socket memory scales with friend count — which is why `ws_idle.js`
varies friend count and reports memory per socket. If those two queries turn out
to be a real share of connect cost, the fix to reach for first is making them
cheaper or lazier for *everyone*, not a flag.

**The pre-serialized/fastlane broadcast for `lobbies`.**
Resolving the host once removes the term that scaled with subscriber count;
what is left is one map build and one encode per socket, and those cannot be
shared while sockets have per-socket dedupe and a per-socket JSON/protobuf
format. Whether that residue matters is exactly what `lobbies_storm.js`
measures — after the number, not before.

## Measure in `MIX_ENV=prod`, or measure nothing

The same `me` scenario, same machine, same minute:

| mode | req/s | median |
|---|---|---|
| dev | 293 | 50 ms |
| prod | 18,918 | 0.6 ms |

Sixty times. Dev mode checks for changed files on every request, so a dev-mode
run measures Phoenix's code reloader and the application is not visible behind
it. Everything measured before this was noticed — including the first pass of
the local report — was that. The bench image is `MIX_ENV=prod` already; the
trap is local iteration, where it is tempting to point the harness at the
server that happens to be running.

## Fixed while building the harness: the SQLite pool

The first thing the harness found, and it found it by being run rather than by
being reasoned about. Concurrent `POST /api/v1/login/device`, each creating a
user, on a laptop dev server (SQLite, `stress_hook` only, limits off):

| concurrency | pool 10 | pool 1 |
|---|---|---|
| 2 | 30 ms | — |
| 3 | 340 ms | — |
| 6 | 10-21 s, some `500` | 44-66 ms |
| 12 | mostly `500` after ~11 s | 38-94 ms |

Superlinear, and it was **not** the database: the failing statement was the
plain `INSERT INTO users`, but an external `sqlite3` process could take the
write lock in 0.2 s during the exact window the app's own inserts were waiting
out their full 10 s `busy_timeout`. The lock was free; the app was thrashing for
it. Ten pooled connections raced the same single writer, and
`sqlite3_busy_timeout` retries with a backoff that is neither fair nor FIFO —
a connection that sleeps loses the lock to a newcomer and sleeps longer.

One connection turns that race into a queue: writes serialize in the BEAM,
first-come-first-served, at no cost. The adapter default in
`GamendWeb.HostRuntime` is now 1 for SQLite (10 on Postgres, unchanged), and
`config/dev.exs` matches it. Reads do not pay for it — 12 concurrent `GET /me`
were 39-51 ms at pool 1 versus ~50 ms at pool 10, because WAL keeps readers off
the write lock and most reads are cache hits anyway.

Two things worth carrying into the matrix:

1. **WAL was already on and did not help.** It is the right setting and it is
   why reads stayed fast, but it addresses reader-vs-writer, and this was
   writer-vs-writer.
2. **`busy_timeout` treats the symptom.** Raising it (which landed just before
   this) converted fast `500`s into slow `200`s; it did not reduce contention.
   Both are now moot at pool 1, but on the Postgres cells the pool goes back to
   10 and this reasoning does not apply — which is exactly the SQLite-vs-Postgres
   difference the matrix exists to quantify.

Whole-suite effect at 5 VUs, same machine, before and after: `auth_device` 0.6
rps at 43% errors becomes 64.8 rps at 0%; `friends` 0.3 becomes 102.8; `quests`
0.1 becomes 88.7. Every scenario green.

## Measured locally, before the matrix

Written up in full, with the machine's specs, at
[stress/baselines/2026-08-19-macbook-air-m1.md](../../stress/baselines/2026-08-19-macbook-air-m1.md).
All on one MacBook Air M1 (8 cores, 16 GB), `MIX_ENV=prod`, generator on the same box —
so read the *shapes*, not the absolute numbers. The Fly cells exist because a
generator sharing the server's cores cannot be trusted past saturation.

**1. Login side-effects moved off the request path.** A login wrote up to three
rows synchronously: the user, `last_seen_at`, and the activity day. The last two
are fire-and-forget by construction, so they joined the `Gamend.Async` block
that already carried the login hooks. Signup, before → after:

| VUs | before | after |
|---|---|---|
| 5 | 687 rps · 36.3 ms | **1,215 rps · 2.4 ms** |
| 15 | 1,611 · 10.1 ms | **1,940 · 7.6 ms** |
| 60 | 1,087 · 51.1 ms | **1,483 · 34.7 ms** |
| 240 | 877 · 297.9 ms | **1,267 · 91.3 ms** |

**2. SQLite vs Postgres, same machine.** Postgres 15 over a unix socket, pool
10, against SQLite pool 1:

| | 5 VUs | 60 VUs | 240 VUs |
|---|---|---|---|
| signup (rps) | 2.56x PG | 1.10x PG | 0.91x PG |
| signup (p95) | 3.2 vs 12.8 ms | 66 vs 156 ms | 382 vs 687 ms |
| hook RPCs (rps) | 2.08x PG | 1.51x PG | 1.28x PG |
| cached read (rps) | 0.89x PG | 0.88x PG | 0.89x PG |

Three things worth carrying forward. Postgres wins the write paths on
*latency* far more clearly than on throughput — half the p95 at every level.
SQLite wins cached reads by ~10%, which is what a local file with a cache in
front of it should do. And **both adapters decline as concurrency rises**,
which was not the expectation: if the fall were SQLite's single writer,
Postgres would not do it too. On a box where the generator, the server and the
database share eight cores, the leading explanation is oversubscription rather
than a lock — and separating the generator is exactly what the matrix does.

**3. Memory per idle socket: ~24 KB of process memory, flat in account size.**

Measured with a plugin RPC (`stress_socket_memory`) reading
`Process.info(:memory)` on live processes, median of 40 at 300 sockets:

| friends | channel | `cu_last` memo | WebSocket transport | total |
|---|---:|---:|---:|---:|
| 0 | 2.8 KB | 0.9 KB | 21.6 KB | **24.4 KB** |
| 10 | 2.8 KB | 0.9 KB | 21.7 KB | **24.5 KB** |
| 20 | 2.8 KB | 0.9 KB | 21.7 KB | **24.5 KB** |

A socket retains almost nothing about its player, the dedup memo included, and
friend count does not move it. Against Nakama's ~150 KB per connection this is
light; 20,000 sockets is ~0.5 GB of process memory. Size hardware from RSS
instead (60-100 KB per socket, which also carries binaries, Presence and
Registry ETS, and allocator slack) — process memory answers a different
question: whether the code holds anything it should not. It does not.

Two traps worth writing down, because each produced a confident wrong answer
before the right one:

- **Bandit serves HTTP and WebSocket from one `DelegatingHandler` module.**
  Sampling transports by module name mixes idle sockets with in-flight HTTP
  requests — 601 handler processes existed for 300 sockets — and the median then
  tracks the request mix, which reads exactly like "memory grows with friend
  count". The app's `:ws_socket` registry is the discriminator.
- **Seeding inside the sample window.** RSS runs showing 400-530 KB per socket
  were writing 5,000-10,000 friendships while being measured.

Nothing needed fixing, so nothing changed. Forced post-join GC, channel
hibernation and `fullsweep_after` were each tried against the bad measurement
and none are in the tree.

Full write-up, with the machine's specs, in
[stress/baselines/2026-08-19-macbook-air-m1.md](../../stress/baselines/2026-08-19-macbook-air-m1.md).

## Where per-socket memory goes

Measured at 3,000 idle sockets against idle, single scheduler:

| category | per socket |
|---|---:|
| binary | **105 KB** |
| processes | 43 KB |
| ETS | 7 KB |
| total (RSS) | ~154 KB |

Two thirds is binary, and it is not application data — the channel state,
assigns and dedup memo live in `processes` (43 KB) and the PubSub, Registry,
Presence and cache entries live in ETS (7 KB; every ETS table in an idle node
totals 3.8 MB). The binaries are **socket buffers**: a connected socket reports
`buffer: 408_300` because macOS auto-tunes `recbuf` to ~470 KB and the inet
driver sizes itself from that.

So the socket ceiling is set by an OS default rather than by gamend.
`GAMEND_REALTIME_SOCKET_BUFFER_KB` exists to cap the driver's read buffer but
defaults to **0**, meaning off: on macOS an accepted socket recomputes its
buffer from the kernel's negotiated `recbuf`, so the setting is discarded, and
whether Linux honours it is a prediction. Confirming that on the first Fly cell
— measuring per-socket memory with the setting off and on — is what would turn
it on by default.

The obvious alternative, capping `recbuf`/`sndbuf`, is deliberately not done:
that bounds the memory by shrinking the TCP window, capping throughput at
window/RTT (~2.6 Mbit/s for 32 KB over 100 ms), which the same listener's Godot
web exports and avatar uploads would pay for.

Ruled out by measurement: compression (no effect) and `max_frame_size`
(8 % effect).

Also worth stating plainly: **the "sockets in 3 GB" figures are projections from
a measured marginal cost**, not runs against an enforced limit. The BEAM has no
VM-wide memory cap — `+hmax` bounds one process, everything else is a cgroup or
container limit where exceeding it kills the VM. A true ceiling test runs under
such a limit and finds where it dies.

## Bottlenecks: four read from the numbers, one real

| hypothesis | verdict |
|---|---|
| matchmaking's 3.1 s is the sweep interval | **true** — a join now nudges the worker; 3,146 ms → **66 ms**, scenario 40 → 477 req/s |
| advisory locks (+8 ms on PG) hurt hot write paths | false — `Economy.grant` is lock-free; the 8 ms was the synthetic `stress_kv_write_locked` probe |
| `quest_claim` takes two locks | false — it takes none; atomic conditional `UPDATE` plus a lock-free grant |
| `page_home` is 4.5x slower on PG, so N+1 | false — 1 query, 6 ms warm |

The lesson for the matrix: a number that looks like a bottleneck is a
*hypothesis about code*, and reading the code is cheaper than acting on the
number. Three of four did not survive that step.

Genuinely open: `Quests.advance_quest` holds a per-(user, quest) advisory lock
because merging objective progress is a read-modify-write of a JSON map. It is
the one hot path where the lock cost is real, and making it atomic across both
adapters is a design change rather than tuning.

## Comparison with Nakama

Their published figures are for **one node at 1 CPU / 3 GB** with the database
on a separate 8-vCPU CloudSQL instance, so a comparison is only worth anything
under the same shape: BEAM pinned to a single scheduler, Postgres as its own
process. Measured that way on the M1:

| operation | Nakama | gamend, 1 scheduler |
|---|---|---|
| user registration | 528/s @ 21.2 ms | 1,037/s @ 13.7 ms |
| custom RPC | ~700-825/s @ 20-27 ms | 2,635/s @ 1.6 ms |
| sockets in 3 GB | 20,277 | ~27,200 |

Ahead on everything they publish, but three asymmetries all run our way — an M1
core is faster than a GCP `n1` vCPU, their database was a network hop away while
ours is a unix socket, and their database node was much larger than their app
node. Read it as "same order, ahead on each operation", not as a multiplier. The
2M-CCU result they publish is a cluster test and has no gamend counterpart until
the horizontal phase.

Full numbers, both adapters, and the capacity model in
[stress/baselines/2026-08-19-macbook-air-m1.md](../../stress/baselines/2026-08-19-macbook-air-m1.md).

## Correctness inside the load test

A benchmark that returns 200s fast while serving stale or wrong data is worse
than a slow one. So the scenarios carry k6 `check`s that are correctness, not
status codes, and `report.mjs` prints the check-failure rate next to latency:

- **Read-your-write through the cache:** `profile_write.js` PATCHes a name then
  GETs `/me` and asserts the new name; `hooks_rpc.js` writes a KV value then
  reads it via `GET /kv/:key`; `lobbies_http.js` transitions state then reads
  the lobby. Every write scenario has one. Single-node this proves cache
  invalidation; on the later 2-node run it proves L2 (write on A, read on B).
- **Event delivery:** `lobby_ws.js` and `chat.js` assert the event *arrives* (a
  timeout is a failed check, plus a Trend of how long it took);
  `matchmaking.js` asserts `match_found` names a lobby the caller is in.
- **Cache hit ratio** from the PromEx cache plugin, per scenario, is in the
  report — a read scenario with a 40 % hit ratio is a finding.

**Server-side errors:** three signals, all captured by `matrix.sh` per run:

1. k6 `http_req_failed` and `checks` — the client view.
2. PromEx: `phoenix` 5xx counters, BEAM process/crash metrics, DB queue time,
   and `[:gamend, :rate_limit, :deny]` (must be 0 — proves the limiter is off).
3. `fly logs -a gamend-bench` tee'd to `results/<run>.log` for the duration;
   the report greps `[error]`, `[warning]` and `** (` counts per run. A run with
   fast p95 and 30 `DBConnection.ConnectionError`s in the log is a failed run.

## Logging cost

Already mostly handled: `access_log_level` defaults to `:debug` and prod
compiles at `:info` (`config/prod.exs` purges below `:info`), so **per-request
access lines cost nothing in prod today**; sockets have `log: false`. What is
left at `:info` is per-event application logging (channel joins, hook loads,
Oban) plus the admin in-memory log buffer handler. Erlang's `logger` is async
with overload protection (`sync_mode_qlen` / `drop_mode_qlen` — it drops under a
storm rather than blocking callers), so the cost is formatting + stdout, not
back-pressure. Two things to do rather than guess:

- One `suite.sh` run on B with `GAMEND_OBSERVABILITY_LOG_LEVEL=warning` vs the
  default `info`. If the delta is < 5 % there is nothing to chase.
- The `[warning]` grep above doubles as an audit: any warning that fires *per
  request* under load (e.g. `LobbiesChannel: unknown event`) is either a bug or
  a log line that should be `debug`.

Not proposed: sampling or a different logger backend — the signal for
per-request questions is PromEx, not logs, and that is already the design.

## Global topics (`lobbies`, `groups`)

They cannot "kill everything by default": both are behind `FeatureGate`
(`list_lobbies` / `list_groups`, off by default) *and* a client must explicitly
join the topic — a player in a match receives nothing. What `lobbies_storm.js`
measures is the cost when they are on and a lobby-browser screen is open on N
clients. The hypothesis is about *how* the fan-out is done: `Gamend.Lobbies`
broadcasts a raw tuple over PubSub and every subscriber channel process
serializes it independently — N encodes per event. If it shows, the fix is known
and local: encode once and push a pre-serialized `Phoenix.Socket.Broadcast` (the
fastlane path), and/or coalesce list updates on a ~250 ms tick. After the
number, not before.

## Web pages

`web_pages.js` GETs the dead-rendered LiveView pages at low VUs. It is cheap
and tells you whether a page render is heavier than the API call behind it.
Driving the LiveView **socket** (join with CSRF + session cookie, then push
events) is not in this round: it is a different protocol to reproduce in k6,
the web UI is not what games ship, and the page-vs-API comparison is answered
by putting a page next to its API twin in the same table.

The pages are `/`, `/groups`, `/users/log_in` and one blog post — not the
`/lobbies` and `/users/log-in` this spec first assumed. There is no `/lobbies`
page route in this build, and the login page uses an underscore, so `/groups`
is the one with an API twin (`GET /api/v1/groups`) and stands in for the
comparison.

## What we measure

k6: rps, p50/p95/p99, error rate, check failures, iterations; `Trend`s for
channel-event delivery latency and time-to-match; VUs at SLO breach; sockets
established per second and p95 connect+join latency; derived memory per socket.
**SLO for the capacity number:** HTTP p95 < 300 ms and errors < 1 % sustained
for 60 s; channel event delivery p95 < 500 ms; check failures 0.

Server (fly-metrics.net, PromEx): CPU %, RSS, run-queue length, scheduler
utilization, process count, Ecto `queue_time` / `query_time` p95, Nebulex hit
ratio, channel joins/messages, rate-limit denies, Oban queue depth.

## Phases

1. **Plumbing (½ day).** `gamend-bench` + `gamend-k6` + Postgres app on Fly;
   `[metrics]`; one end-to-end run to prove results and Grafana come back.
2. **Harness (1–2 days).** `lib/`, the isolated scenarios with their checks,
   `suite.sh`, `report.mjs`, `stress_hook`. Iterate locally per "Running
   locally". Commit `stress/README.md`.
3. **Journeys (½–1 day).** `player_session.js`, `ws_idle.js`, `ws_storm.js`,
   `lobbies_storm.js`, `soak.js`.
4. **Matrix (1 day, mostly machine time).** `matrix.sh` over A–H; commit
   `stress/baselines/`; blog post with the capacity-per-cell table, the
   per-operation SQLite-vs-Postgres table, and the estimates above with the
   actuals next to them.
5. **Fixes.** Each fix re-runs `suite.sh` on B (SQLite) and F (Postgres) and
   diffs against the baseline; that diff is the PR's evidence.
6. **Keep it honest (optional).** A CI job that runs `suite.sh` at 20 VUs for
   10 s against `docker-compose.yml` with loose thresholds (no 5xx, no check
   failures, p95 < 1 s) — a tripwire, not a benchmark.

## Out of scope for this round

OAuth/Steam/Apple; LiveView socket flows; WebRTC DataChannel RPC and signaling
(needs real peers; `clients/test_js_pb.mjs` covers correctness); push delivery;
storage uploads; multi-region.

## CONTRIBUTING checklist (what applies)

- **Functionality:** the harness's only server code is
  `modules/plugins_examples/stress_hook`, a normal plugin; moving `bench_*` out
  of `example_hook` is the only change to existing code. The connect-path fixes
  above are separate from the harness and land on their own.
- **Tests:** plugin RPCs get the same test shape as `example_hook`'s. Harness
  scripts are validated by running (`k6 run --vus 1 --iterations 1` per script,
  listed in `stress/README.md`), not unit-tested. The connect-path fixes need
  unit tests of their own: the per-user socket limit still trips at the limit,
  `last_socket?/1` still answers correctly across two sockets, `PresenceWriter`
  coalesces and still fires the hooks exactly once per transition, and the join
  opt-outs suppress only what they name.
- **Finish:** `stress/README.md`; a `priv/docs` ops guide page ("Load testing")
  linking to it and the results; `CHANGELOG.md` `[added] load-test harness` plus
  `[changed]` for the connect-path fixes and the two new realtime pool settings;
  blog post.
