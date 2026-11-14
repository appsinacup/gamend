<!-- api-lint: unimplemented -->

# Replays — recorded sessions from a deterministic client

Design spec. Builds on **Object storage** (Phase 0, shipped), `Gamend.ClientLogs`
(shipped) and `Gamend.Results` (shipped). Sibling of
[cloud-saves.md](cloud-saves.md) — both are thin, indexed layers over
`Gamend.Storage`, and they should share its presigned upload path unchanged.

Goal: let a game upload a **recorded session** — the inputs it was fed, not the
world it produced — so a developer can pull a run back out and re-simulate it,
and so the server can tell two players in the same match that their simulations
**parted at tick N**.

The client half already exists. Balaur (the engine, separate repo) records
sessions today; nothing receives them. This spec is the receiving end.

## What the client produces

Balaur's `crates/balaur_core/src/replay.rs` writes **JSON Lines**: a `Header`
on the first line, then one `Frame` per tick, flushed per frame so a crashed
session still leaves a usable file.

```jsonc
{"format":1,"project":"my-game","seed":7}
{"tick":0,"dt":1031798784,"sources":{"input":{…},"gamend":[]},"digest":11833882917552452801}
```

| field | meaning |
|---|---|
| `format` | bumped when a change makes an older file unplayable; currently `1` |
| `project` | the project the session ran, so a replay needs only the file |
| `seed` | the RNG stream's starting position |
| `dt` | the step as **raw f32 bits** — a replay that rounded would diverge for reasons unrelated to the bug |
| `sources` | per-tick external input, keyed by subsystem (`input`, `gamend`, …) |
| `digest` | hash of the whole world at the end of that tick |

Produced by `balaur run <project> --fixed-tick --record session.blr`, and
consumed by `balaur replay session.blr --verify`, which re-simulates and stops
at the first tick whose digest disagrees.

Two properties matter to us:

- **The Balaur client replays by itself.** The Balaur SDK is a script over
  the engine's `http` and `websocket`, both replay sources that route their
  I/O through `replay::ExternalIo`, whose `start` is a no-op while a replay
  plays. So a recording of an **online** session replays offline: the
  recorded server replies are re-fed and no request is made. A session
  against this server is reproducible without this server.
- **The digest is per tick, in the file.** That is what makes cross-player
  desync detection possible here without an engine.

## The size question — records inputs, but not cheaply

"It records inputs, not state" is true and is the reason a replay is worth
storing at all. It is **not** currently the reason to expect a small file.

`add_replay_resource::<InputSnapshot>("input")` serializes the *whole*
`InputSnapshot` every tick via `serde_json::to_value`, and `InputSnapshot`
derives plain `Serialize` with no `skip_serializing_if`. So every tick writes
every field — three 8-element bool arrays, three float pairs, five empty
collections — whether or not anything happened. An idle tick and a busy tick
cost the same.

Computed from the format (idle input snapshot 391 B, whole frame line 486 B):

| | 5 min @ 60 Hz | per hour |
|---|---:|---:|
| current format, raw | 8.9 MB | 107 MB |
| current format, gzip -6 | 0.50 MB | 6 MB |
| delta-encoded, keyboard game, gzip | 6 KB | 72 KB |
| delta-encoded, mouse moving every tick, gzip | 121 KB | 1.4 MB |

`balaur/docs/DETERMINISM.md` claims "Minutes of play is kilobytes." With the
current writer, minutes of play is **megabytes**; the claim describes the format
it could have rather than the one it has. The gap is ~80x for a keyboard game.

**This is an engine-side finding, not a server-side one**, and it is worth
fixing there first — emit a frame only when a source changed, and write the
digest at a lower rate than the simulation. But this spec must work with the
format as it stands, because a server cannot assume the client compressed well.

## Two tiers, because they answer different questions

Storing whole recordings for every session is the wrong default: it is the
expensive half, and most sessions are never opened. Split it.

### Tier 1 — the digest trace (always on, small, in the database)

A **sampled digest trace**: `(tick, digest)` at a configured rate (default 1 Hz,
not 60), plus the header. 5 minutes is ~300 pairs.

This is the tier that earns its place, because it answers a question no single
client can answer alone: **two players in one lobby disagree about what
happened**. Each uploads its trace; the server compares them and reports the
first tick where they differ. That is a sequence comparison over integers — no
simulation, no engine, nothing Elixir cannot do — and it turns "it desynced
sometimes" into "run `balaur replay <file> --entries-at 4213` on both machines",
which is exactly the workflow `DETERMINISM.md` already documents.

Stored as a column on the replay row: the traces are small, they are compared
server-side, and they must survive whatever happens to the blob.

### Tier 2 — the full recording (on demand, on object storage)

The `.blr` file itself, uploaded through `Gamend.Storage`'s existing presigned
flow, exactly as avatars and (per cloud-saves) saves do. Bytes never stream
through the app.

Uploaded when one of these is true, so the common case costs nothing:

- the client asks to (a developer build, a "report a bug" button);
- the session was **flagged** — a Tier 1 comparison found a divergence, or the
  client reported a crash;
- a sampling rate says so (`capture_policy`, below), for a share of sessions.

## Why not verify server-side

Gamend cannot replay a balaur session. Re-simulation requires the engine, the
project and the game's own script — none of which live here, and none of which
should. Any design that has the server "check the replay" is wrong at the
premise.

What the server can do is compare what clients report about the *same* run, and
store the evidence. That is the whole scope, and it is deliberately smaller than
it first sounds.

## Data model (both adapters)

Modelled on `client_sessions`: the row is an **index**, not the content. See
`Gamend.ClientLogs`'s moduledoc for the reasoning — it applies unchanged.

**`replays`**

| column | notes |
|---|---|
| `replay_id` | client-generated, like `client_session_id` — the client must name it before it can reach us; bound to an owner on first write |
| `user_id` | `belongs_to`, nullable; adopted on login exactly as a client-log session is (`bind_owner/2`) |
| `client_session_id` | the correlation key into `Gamend.ClientLogs` — same run, client's own log lines |
| `lobby_id` | the correlation key into `Gamend.Results` — same run, what the server recorded of it |
| `project`, `format`, `seed` | straight from the recording's header |
| `engine`, `engine_version` | `"balaur"` + version; the format is not balaur-specific, and a second engine must not need a second table |
| `tick_count`, `duration_ms` | how long the run was |
| `digest_trace` | Tier 1: `[[tick, digest], …]` at the sampled rate |
| `trace_rate_hz` | what the trace was sampled at, so two traces are comparable |
| `storage_key` | Tier 2, nullable — null until a full recording is uploaded |
| `byte_size`, `checksum` | of the uploaded blob (client-supplied SHA-256) |
| `platform`, `app_version`, `build` | reuse `ClientLogs.Session`'s vocabulary and validation verbatim |
| `flagged`, `flag_reason` | keeps the run past the ordinary retention window; set by divergence detection or by the client |
| `diverged_at_tick` | first tick where this run disagreed with a peer, nullable |
| `started_at`, `last_seen_at` | |

Indexes: `unique_index(:replay_id)`, `index([:lobby_id])`,
`index([:client_session_id])`, `index([:user_id, :started_at])`,
partial `index([:flagged])` (following `partial_null_heavy_indexes`).

Blob keys are deterministic — `replays/<user_id>/<replay_id>.blr.gz` — via
`Storage.put/2` with an explicit key rather than `build_key/3`'s random scheme,
so a replay maps to exactly one object and pruning is unambiguous.

`Gamend.Storage` needs one addition: `application/gzip` (and the `.blr.gz`
extension) in the upload allow-list, plus a gzip magic-byte case in
`sniff_content_type/1`. The existing per-object and per-owner caps then apply
with no further work.

## Correlation is the point

One run, three views, already keyed the same way:

```
client logs      client_session_id ──┐
results          lobby_id ───────────┼──> replays
input recording  replay_id ──────────┘
```

`Gamend.ClientLogs` already stamps `client_session_id` onto server-side lines
from the `x-gamend-session` header, and already links a session to its lobbies
through `session_lobby_ids/1`. So a replay row makes the last connection: the
player's log lines, the server's record of the play, and the exact inputs, from one
id. That is the feature; the storage is plumbing.

Admin pages cross-link in both directions —
`admin_live/logs.ex` already links a lobby id to its plays at `/admin/results`, and
this adds the third corner.

## API

```
GET    /api/v1/replays/policy      capture policy (mirrors client_logs/policy)
POST   /api/v1/replays             open a replay: header + trace, returns an
                                   upload ticket iff a blob is wanted
PATCH  /api/v1/replays/:id         append trace, confirm the blob, close the run
GET    /api/v1/replays/:id         one replay (owner or admin)
GET    /api/v1/replays             the caller's own replays, paginated
```

`policy` is what makes the tiers cheap: the client asks at startup whether to
record at all, at what trace rate, and whether to upload the blob — the same
shape and the same reasoning as `ClientLogs.capture_policy/0`, so a game can be
switched from "traces only" to "full recordings" without shipping a build.

Auth is **required** here, unlike client logs. The argument for optional auth
there was that pre-login entries are the ones worth having; a replay is a whole
session and has an owner by construction.

Admin API parity: list/inspect/delete any user's replay, and the divergence
report for a lobby.

## Settings (`Gamend.Settings.Provider`, group `:replays`)

`enabled` (false), `trace_rate_hz` (1), `blob_upload` (`off` | `flagged` |
`sampled` | `always`, default `flagged`), `blob_sample_rate` (0.0),
`retention_days` (14), `retention_flagged_days` (90) — the last two mirroring
`Gamend.ClientLogs` exactly, keyed off `last_seen_at`, wired into
`Gamend.Retention` beside `prune_client_sessions/0`. Pruning a row **must**
delete its blob; that is the one thing this adds over the client-logs sweep.

Limits (`Gamend.Limits`): `max_replay_bytes`, `max_replay_trace_points`,
`max_replays_per_user`.

## Deferred / rejected

- **Server-side re-simulation: rejected.** See "Why not verify server-side".
  The server has no engine and should not grow one.
- **Storing the recording in a database blob table: rejected as the default.**
  A content-addressed blob table would dedupe nicely, but a
  0.5 MB gzipped row per 5-minute session puts megabytes per player per day
  into a table that a SQLite deployment backs up whole. Object storage is where
  this shape of data already goes here. Revisit **if** balaur delta-encodes: at
  6 KB per 5 minutes the calculus genuinely flips, and a DB blob would then be
  the simpler system.
- **Live spectating / replay streaming: defer.** A different problem (latency,
  fan-out) wearing the same word.
- **Rollback netcode using balaur's `SnapshotRing`: out of scope.** That is
  engine-side, it is for late inputs within a live match, and its own docs note
  it does not yet cover entities spawned or freed since the snapshot.
- **A `replay_uploaded` realtime event: defer.** v1 is pull.

## Open questions

1. **Does balaur delta-encode first?** It changes the storage answer (above) and
   nothing else in this spec. Worth doing there regardless — an 80x file-size
   win for a format change, and it makes its own documented claim true.
2. **Who compares traces?** Cheapest is on write: when a second replay arrives
   for a `lobby_id`, compare against the first and flag both on divergence.
   Alternative is a periodic sweep. On-write is simpler and catches it while
   the blob-upload decision is still live — which is the point of flagging.
3. **Is `digest_trace` a column or a table?** A JSON column is one row per run
   and no join; a `replay_trace_points` table makes "first differing tick" a SQL
   query. At 300 points per run the column is almost certainly right.

## Definition of done (CONTRIBUTING)

- [ ] Migration for `replays` applies on SQLite **and**
      `GAMEND_DB_ADAPTER=postgres`; indexes as above.
- [ ] `Gamend.Storage` accepts `application/gzip` with a magic-byte check;
      per-object and per-owner caps enforced.
- [ ] Owner binding on first write (`bind_owner/2` semantics), so a second
      device cannot write into someone else's run.
- [ ] Trace comparison flags both runs and records `diverged_at_tick`.
- [ ] Retention prunes rows **and** their blobs; flagged window honoured.
- [ ] Paginated `list_*`/`count_*`; `Limits` caps enforced.
- [ ] Admin page + `/admin` card + route + nav + `admin_pages_render_test`;
      cross-links to `/admin/logs` and `/admin/results`, and those two
      link back.
- [ ] Docs, `.env.example`, CHANGELOG, README, `api_spec.ex`; i18n 30 locales.
- [ ] Tests: context + controller + admin + LiveView, both adapters (Local +
      an S3 mock); round-trip a recording, force a divergence between two
      traces and assert the tick, prune and assert the blob is gone.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green;
      `mix gen.sdk` clean; `mix gamend.api.lint` clean.
