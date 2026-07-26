# Server time, state revision, action idempotency

Goal: give real-time games the three things a client needs to predict server
state and the two things a server needs to survive an unreliable network —
without core taking any position on game physics.

Core supplies: **`server_now`**, a monotonic **`revision`** per lobby, and
**idempotent actions**. Latency compensation stays in the game, on top of these.

## Why core

Polyglot's `PLAN_NETWORKING.MD` (in the `gamend_polyglot` repo) opens
with an inventory of what exists: *"No current ping, RTT, client timestamp,
sequence, or state revision protocol found."* That is accurate for core too —
`grep state_revision` returns nothing.

The consequences it documents are the generic ones, not polyglot's:

- A player with 1 s RTT loses to an obstacle they visibly beat, because the
  server resolves at receipt time and the client has no way to say when it
  acted.
- A retried or duplicated action applies twice; a reordered pair applies
  backwards. Nothing in core detects either.
- A client cannot predict between calls, because payloads carry no server clock
  to anchor to, so every game re-invents "what time does the server think it is"
  from HTTP `Date` headers or guesses.

Every action game hits all three, none of them can be fixed from inside a
plugin (the RPC envelope, the channel and the lobby writes are core's), and the
fix is small once the seams exist.

## Piece 1 — `server_now`

- `GET /time` and a `get_server_time` channel call, both returning
  `%{server_now: <ms since epoch>, revision: <lobby revision | null>}`.
- `server_now` added to lobby payloads and to every lobby realtime event.

The client measures RTT across a few samples, estimates an offset, and from then
on renders in server-time space. Cheap, boring, and the prerequisite for
everything else.

Timestamps are `System.system_time(:millisecond)` — wall clock, because the
client is comparing against its own wall clock and because the value crosses
nodes. Durations *within* the server (cooldowns, deadlines) keep using
monotonic time where they already do; the two must not be mixed, and the
moduledoc says which is which.

## Piece 2 — `lobbies.revision`

One `bigint` column, `default 0`, incremented in the same `UPDATE` as any change
to lobby `metadata` or `state`:

```sql
UPDATE lobbies SET metadata = $1, revision = revision + 1 WHERE id = $2 AND revision = $3
```

Two uses, one column:

**Optimistic concurrency.** `Lobbies.update_lobby/3` accepts
`expected_revision:`; a mismatch returns `{:error, {:stale_state, current}}`
with the current payload rather than clobbering. This is the compare-and-swap
that lobby metadata has never had — complementary to
[locking.md](locking.md) and [lobby-session.md](lobby-session.md): the lock and
the session *prevent* the race, the revision *detects* one that got through
(another node, a netsplit, an admin edit, a plugin that forgot).

**Client staleness.** Every lobby event carries `revision`, so a client can drop
a frame that arrives out of order after a newer one — which happens routinely
with the existing debounce-and-coalesce path in `ChannelUpdates`.

Passing `expected_revision` is optional. A caller that omits it gets today's
last-write-wins behaviour, so nothing existing breaks.

## Piece 3 — action idempotency

An action envelope on RPC and channel calls:

```jsonc
{ "seq": 41, "client_sent_at": 1753440000123, "observed_revision": 87 }
```

- **`seq`** — monotonic per `(user, lobby)`. The server keeps the last accepted
  `seq` and the last reply in the lobby session
  ([lobby-session.md](lobby-session.md)), falling back to a short-lived cache
  entry when no session exists. A **replay** of the last `seq` returns the
  stored reply without re-executing; an **older** `seq` is rejected with
  `{:error, :stale_action}`; a newer one executes.
- **`client_sent_at`** — passed through to the game untouched, never trusted by
  core, never persisted as a timestamp.
- **`observed_revision`** — what the client acted on. Core only echoes it to the
  game; a game that cares rejects or rebases.

Replies gain `server_now` and `revision` so a client always knows what it just
observed. All three envelope fields are optional; a client that sends none gets
exactly today's behaviour.

Cache retention: last-reply memory is per session (dies with it) or a
`GameServer.Cache` entry with a short TTL — this is deduplication of a retry,
not durable exactly-once delivery, and the docs say so plainly. Anything that
must be exactly-once (a purchase, a reward) uses the idempotency keys the
economy and quests already have.

## What core does *not* do: latency compensation

Rewinding a resolution to "when the player claims they acted" is a **game**
decision — how far, for which actions, whether a 400 ms rewind is fair in
ranked. Core supplies the inputs and one helper, and stops:

```elixir
Netcode.effective_now(client_sent_at, receipt_now, cap_ms: 500, floor: last_action_at)
```

Pure, documented with the anti-cheat rules polyglot derived, defaulting to
`receipt_now` when the client sent nothing:

- never accept a future `client_sent_at`;
- never rewind before that user's last accepted action;
- never rewind more than the cap;
- **never** apply compensation to cooldowns, rate limits or reward eligibility —
  only to "did this action beat that event?".

The cap is a declared setting (`Limits`, `max_latency_compensation_ms` →
`GAMEND_LIMITS_MAX_LATENCY_COMPENSATION_MS`, default 500) so a host
can bound what any plugin may claim, and the amount used is returned to the
caller for logging and tuning.

## Wire and SDK

- `server_now` + `revision` on lobby payloads and lobby events; protobuf fields
  added to the existing messages in `proto/gamend_realtime.proto` (new optional
  fields, so old clients decode unchanged), `EventCodec` clauses, `GamendProto.gd`
  handling.
- SDK: `get_server_time()`, an offset-tracking helper that keeps a rolling RTT
  estimate, and an action envelope builder that increments `seq` per lobby.
  The Godot addon exposes `Gamend.server_time_ms()` — a client should never call
  `Time.get_unix_time_from_system()` for gameplay again.

## Admin / metrics

- Lobby detail shows current `revision` and last write time.
- PromEx: counter of stale-action rejections, counter of stale-revision
  rejections, histogram of observed `client_sent_at` skew. The skew histogram is
  the one that pays for itself — it tells you whether clients have their clocks
  synced before you tune any cap.

## Alternatives considered

- **`updated_at` as the revision.** Timestamp resolution collides under load
  (two writes in the same millisecond), and clock skew between nodes makes
  ordering unsound. A counter is one column and no ambiguity.
- **A global revision per server** rather than per lobby. Contention on a single
  counter for no benefit; clients only ever compare within one lobby.
- **`Lock`/session only, no revision.** Serialization prevents concurrent
  writers on the happy path but says nothing about a client acting on a stale
  view, which is the more common case (the player's screen is always behind).
- **Full server-side rollback netcode** (rewind world state, re-simulate).
  Core does not own world state and never will — the session holds no
  authoritative state by design. Games that need rollback build it above these
  primitives.
- **Trusting `client_sent_at` uncapped.** That is a "shoot anything, claim you
  shot it earlier" cheat with extra steps.

## Phasing

1. **`server_now` + `GET /time` + SDK offset helper.** Standalone, useful
   immediately, no schema change.
2. **`revision`** column, optimistic `update_lobby/3`, revision on events.
3. **Action envelope** (`seq` dedupe, `observed_revision` passthrough) and
   `Netcode.effective_now/3`.

Each phase ships alone and each is opt-in from the client's side.

## Definition of done (CONTRIBUTING)

- [ ] Migration adds `lobbies.revision bigint default 0`; applies on SQLite
      **and** `GAMEND_DB_ADAPTER=postgres`.
- [ ] `GET /time` + channel `get_server_time`; `server_now` on lobby payloads
      and every lobby event.
- [ ] `update_lobby/3` accepts `expected_revision:` and returns
      `{:error, {:stale_state, current}}`; omitting it preserves today's
      behaviour exactly.
- [ ] Revision increments in the same statement as the write (no read-then-bump).
- [ ] Action envelope: replayed `seq` returns the stored reply without
      re-executing; older `seq` rejected; missing envelope behaves as today.
- [ ] `Netcode.effective_now/3` is pure, capped by
      `max_latency_compensation_ms`, never rewinds past the last accepted
      action, and is documented as never applying to cooldowns or rewards.
- [ ] Protobuf fields added as optional; old clients decode unchanged; Godot
      addon updated.
- [ ] SDK: server-time helper, RTT offset tracking, envelope builder,
      `mix gen.sdk` clean.
- [ ] Tests both adapters: concurrent updates with `expected_revision` (one
      wins, one gets `:stale_state`), duplicate/reordered/late actions, event
      ordering by revision, and the four `effective_now/3` anti-cheat rules.
- [ ] Admin revision display; PromEx counters + skew histogram.
- [ ] `max_latency_compensation_ms` declared on the `Limits` provider,
      `.env.example` regenerated; docs (Lobbies, Realtime, server-scripting),
      `api_spec.ex`, CHANGELOG, i18n.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; example plugin
      warning-free.
