# Ready check — one primitive, two bindings

Design spec for [issue #16](https://github.com/appsinacup/game_server/issues/16)
("ready check to matchmaking and lobbies, along with match status").

Goal: one core primitive — *"these players must each answer before this thing
proceeds"* — bound in two places core already owns: **matchmaking** (accept the
match you were paired into) and **lobbies** (ready up before the host starts).

**Status:** Phase 1 shipped — the primitive and the lobby `ready` binding. The
`accept` kind exists and is exercised by tests, but nothing opens one yet:
Phase 2 (matchmaking accept) is the remaining unchecked item at the bottom.

**Amendment (July 2026):** the party became the third subject and the check
grew a `reset/3` verb, turning a `ready` check into a **standing, resettable
board** on both containers. See "Party boards and reset" below. A player now
holds at most one open check *per lane* (match lane: lobby/matchmaking; party
lane), `GET /me/ready_check` returns `{lobby, party}`, and
`POST /me/ready_check` takes a `scope`.

## Two features hiding under one name

| | Matchmaking **accept** | Lobby **ready** |
| --- | --- | --- |
| When | Match formed, no lobby yet | Inside a lobby, before start |
| Answer | One-shot, irrevocable | A toggle, flipped freely |
| A "no" | Kills the match for everyone | Nothing — the check waits |
| Deadline | Mandatory (10–20 s) | Optional, defaulted on |
| On timeout | Dissolve the match | Report who stalled; **the host decides** |
| Who opens it | The server (the sweep) | The host |
| Buildable by a plugin today? | **No** | Yes — badly |

Same shape underneath: a participant set, one answer per participant, a
completion predicate, a deadline, and a resolution. The two differences —
**what a "no" means** and **whether an answer can be taken back** — are one
enum, not two features.

## Why core

**Matchmaking has no accept phase at all.** The sweep claims a group and
`Matchmaking.Match.create/1` immediately creates a hidden lobby, seats every
player, locks it and broadcasts `match_found`. The only liveness guard is
`prune_offline/0` (a 5-minute grace on `users.is_online`) plus
`UserChannel.terminate/2` cancelling tickets on socket close — neither of which
knows whether the player is *at the keyboard*. A player who queued and walked
away is seated into a ranked match; the lobby then sits locked with an absent
member until retention reaps it.

No plugin can fix this. Seating happens server-side between the sweep's claim
and the broadcast — there is no seam to hold the match open, and nowhere to
record answers (tickets are core's).

**Lobbies have no ready concept, so every game rebuilds it.** Polyglot's version
lives in `metadata["ready"] = %{user_id => bool}`, written by a plugin RPC
(`WordMatch.set_ready/1` → `Lobbies.update_lobby/2`) and read by
`ensure_members_ready/3` before start. Three problems, all structural rather
than polyglot's fault:

1. **Lost updates.** Setting a flag is a read-modify-write of the whole
   `metadata` map with no lock. Two players clicking ready in the same tick lose
   one flag — exactly what CONTRIBUTING forbids ("any read-modify-write must
   hold a lock").
2. **The wrong owner may write it.** `metadata` is castable, so the host can
   rewrite *anyone's* ready flag through `PATCH /lobbies`. Same class of hole
   the lobby-state spec closed for `metadata["game_state"]`.
3. **Nothing clears it.** Flags survive a leave and rejoin, a kick, and the end
   of the match. KV scoped to `(user_id, lobby_id)` *is* wiped on leave
   (`clear_lobby_scoped_kv/2`), but KV cannot be the store either: `PUT /kv` is
   admin-only, so a player cannot write their own per-lobby entry at all.

## Data model

Two tables. The participant set is a **table, not a map**, so one answer is one
single-row write — no read-modify-write, therefore no lock on the hot path.

```
ready_checks
  id, kind ("accept" | "ready"), status ("pending"|"passed"|"failed"|"cancelled"),
  lobby_id (FK lobbies, on_delete: delete_all),
  party_id (FK parties, on_delete: delete_all),
      -- at most one of the two is set; both NULL = a matchmaking check,
      -- whose group exists only as its tickets
  deadline (utc_datetime, null only for kind="ready"),
  opened_by (user_id, null when the server opened it),
  reason (string, null | "declined" | "timeout" | "cancelled" | "reset"),
  resolved_at, metadata (map), timestamps
  unique index [lobby_id] where status = 'pending'   -- one open check per lobby
  unique index [party_id] where status = 'pending'   -- one open board per party
  index [deadline] where status = 'pending'          -- the expiry sweep

ready_check_participants
  id, ready_check_id (FK, on_delete: delete_all), user_id (FK, on_delete: delete_all),
  ticket_id (FK matchmaking_tickets, null for lobby checks),
  state ("pending" | "ready" | "declined" | "timed_out"), responded_at, timestamps
  unique index [ready_check_id, user_id]
  index [user_id]                                    -- see below
```

"One open check per player **per lane**" is **not** an index: it depends on the
*check's* status, not the participant's state, and a player who has already
answered still belongs to the open check. `open/3` enforces it with a join
instead, which the `user_id` index serves along with `for_user/2`. There are
two lanes — the match lane (a check with `lobby_id` set, or a matchmaking
check) and the party lane (`party_id` set) — so a party's standing board never
blocks that party's lobby from opening its own check.

Real `lobby_id`/`party_id` FKs rather than a polymorphic
`subject_type`/`subject_id` pair: a matchmaking check has no subject row to
point at (the group only exists as its tickets), and the FKs buy a
database-level cascade — deleting a lobby or disbanding a party cannot leave
an orphaned check behind. A further subject later (a tournament match) adds
another nullable FK; that is cheaper than losing the cascade on the ones that
exist now.

In Phase 2, `matchmaking_tickets` gains `ready_check_id` and one status,
`awaiting_accept`, so the queue's own invariants (`ensure_none_queued/1`,
`prune_offline/0`, `cancel/1`) stay honest while a check is open. The
**answers** live only in the participants table — the ticket says "this ticket
is inside a pending check", the participant row says what its owner answered.
No duplicated state. (Participants already carry the `ticket_id` side of that
link; only the ticket column and status are deferred.)

Caps in `GameServer.Limits`: `ready_check_timeout_ms` (15 000),
`max_ready_check_participants` (mirrors `max_matchmaking_players`),
`matchmaking_accept_enabled` (**false** — see Compatibility).

### What is deliberately not touched

**`users` gets no ready column.** Membership in this system *is* `users.lobby_id`,
so "the lobby member" and "the user" are the same row — putting a ready flag
there would put it on the hottest row in the database. `users` is cached by
`Accounts` with index keys, and `User.serialize_brief/1` is embedded in every
member list, friend list, party payload and chat author lookup. A ready toggle
would then invalidate the user cache and leak a lobby-scoped, seconds-lived flag
into a dozen payloads that have no business carrying it.

**`lobbies.metadata` gets nothing either** — that is the polyglot shape and its
three bugs.

The rule the model follows: **ready state belongs to the check, not to the
person.** A check is a *moment* — this lobby, these members, this deadline — and
the participant row is the intersection of check × user. It is born when the
moment opens and dies with it. Nothing about a player outlives their answer.

Row lifecycle:

| Event | Effect |
| --- | --- |
| `open/3` | 1 check row + N participant rows |
| A player answers | 1 UPDATE on their own row — never a map merge |
| Passed / failed / cancelled | check row goes terminal, kept as history |
| Member leaves or is kicked | their participant row is deleted, check re-evaluated |
| Lobby deleted | check + participants cascade at the DB level |
| Retention | resolved checks pruned after `RETENTION_READY_CHECKS_DAYS` (7) |

## Where it lives at runtime

**In the database, and nowhere else.** No GenServer, no ETS, no cache:

- Compare `SpectatorTracker` — ETS, no persistence — which is right for
  spectator *counts*: disposable, per-node, nobody cares if a restart loses
  them. A ready check has a deadline, gates a match and is worth auditing, and
  the two players answering it are usually on **different nodes**, so a
  per-node ETS table would need distribution anyway. The DB already is that.
- **No Nebulex cache**, unlike lobbies and users. Reads are a single indexed row
  (`for_user/1` on the `user_id` index) or a `count` grouped by state.
  Caching a value that changes on every click means invalidating on every click.

So the app layer is just `GameServer.ReadyChecks` (context) plus
`ReadyChecks.Check` and `ReadyChecks.Participant` schemas in
`game_server_core/lib/game_server/ready_checks/` — the same shape as every other
context. The only coordination primitives are the ones already in the codebase:
one advisory lock (`:ready_check`, per check id) around respond-then-evaluate,
and one Oban job per deadline.

## What goes over the wire

Two topics, both of which already exist and already reach the client:

| Kind | PubSub topic | Who receives it |
| --- | --- | --- |
| `ready` (lobby) | `lobby:<lobby_id>` | every member — and spectators, who see all lobby events today |
| `accept` (matchmaking) | `matchmaking:user:<id>` | that one player; there is no shared topic before the lobby exists |

```jsonc
// ready_check_started on lobby:<id> — members are not a secret to each other
{ "id": "01J…", "kind": "ready", "lobby_id": "01J…",
  "deadline": "2026-07-25T12:34:56Z",
  "participants": [ {"user_id": "01J…", "state": "ready"}, … ] }

// ready_check_started on matchmaking:user:<id> — counts only, so a pending
// match does not reveal who you were paired with
{ "id": "01J…", "kind": "accept", "deadline": "…",
  "total": 6, "ready_count": 2, "your_state": "pending",
  "match_params": {"mode": "ranked"} }
```

Delivery rules:

- **Not in `serialize_lobby/2`.** The check is its own payload, so `GET /lobbies`
  never pays a query per listed lobby for it. A client's sources of truth are
  `GET /me/ready_check` on connect and the events after that.
- `ready_check_updated` goes through `ChannelUpdates.push/5` keyed by check id,
  so ten people readying inside one debounce window coalesce into one frame and
  an identical state is dropped outright.
- `ready_check_passed` / `ready_check_failed` bypass the debounce with
  `push_event/3` — a resolution is not a state refresh and must not sit in a
  timer.
- Protobuf parity: two messages in `proto/gamend_realtime.proto`
  (`ReadyCheckState`, `ReadyCheckResolved`), clauses in `EventCodec`,
  registration in `RealtimeEvents`, handling in `GamendProto.gd`.

## Behaviour

`GameServer.ReadyChecks`:

- `open(subject, user_ids, opts)` — `subject` is a `Lobby`, a `Party` or
  `:matchmaking`. Inserts the check and its participants,
  broadcasts `ready_check_started`, schedules expiry. Fails with
  `{:error, :already_pending}` if any player is already in an open check in
  the same lane.
- `reset(subject, user_ids, opts)` — quietly cancels the subject's pending
  check (reason `"reset"`, no failed event, no hook) and opens a fresh one.
  The one verb behind every "answers are stale now" moment: rematch, mode
  change, membership change after a resolved board, "force ready" (pass a
  `timeout_ms`).
- `respond(user, ready?, scope)` — resolves the caller's open check in the
  lane `scope` names (`:match` default, or `:party`), writes their participant
  row, then evaluates.
- `cancel(check, reason)` — the host called it off, or the subject went away
  (lobby deleted, match dissolved, admin action).
- `answer_for(check, user_id, ready?)` — server-side answer for a bot or an
  AI-controlled member; never reachable over RPC.
- `for_user(user_id, scope)` / `passed?(subject)` / `not_ready(check)` — reads
  for the API, for a game's own gating, and for the host's kick list.
  `passed?/1` orders by insertion, so a reset (which opens a fresh pending
  check) makes it false again — a rematch cannot ride the previous match's
  pass.

Evaluation is the one place that must not race: two concurrent "ready" writes
can each count the other as still pending and nobody passes (write skew). So
`respond/2` holds `GameServer.Lock.serialize(:ready_check, check_id, …)` around
write-then-evaluate — one new advisory-lock namespace (`ready_check: 11`).
Hooks and broadcasts fire after the lock releases.

**`kind: "accept"`** — the first `declined` fails the whole check immediately;
answers cannot be revoked; the deadline is mandatory and every still-`pending`
participant becomes `timed_out`.

**`kind: "ready"`** — a "no" writes `declined` and leaves the check **pending**;
flipping back to ready is allowed until it passes. On the deadline it resolves
`failed` with everyone still `pending` marked `timed_out` — and that is all core
does. It does **not** kick, does not dissolve the lobby, does not touch the
lobby's state. `ReadyChecks.not_ready(check)` names the stragglers; the host
looks at them and uses the kick they already have. A game that wants auto-kick
writes three lines in `after_ready_check_failed`; core does not decide that a
slow player deserves removal.

Members who join the lobby while it is open are added as `pending`; members who
leave or are kicked have their row removed and the check re-evaluated — kicking
the one straggler can therefore pass the check outright. The party seams mirror
this exactly (`add_party_member/2`, `remove_party_member/2`, wired into party
join/leave/kick); disbanding a party cascades its checks at the DB level.

### Party boards and reset

A party is a persistent group, so its `ready` check is used as a **standing
board** rather than a moment: a game opens one when the party forms (core
never opens one itself), members toggle at leisure, and `reset/3` starts the
answers over whenever they go stale. The same shape works on a lobby — reset
on match end and the next match needs a fresh board, which is what makes
`passed?/1` a sound start gate.

What a party board *gates* is the game's business, exactly like lobby state: a
passed party board fires `after_ready_check_passed` and nothing else. Party
events ride the existing `party:<party_id>` topic. The leader opens/resets via
`POST /parties/ready_check` and cancels via `DELETE /parties/ready_check` —
the same authorization shape as the lobby host.

### Expiry

A durable `Oban` job scheduled at the deadline, idempotent (a no-op if the check
already resolved) — no new supervised GenServer, and it survives a restart,
which a `Process.send_after` would not. The existing matchmaking sweep also
calls `ReadyChecks.expire_due/0` **outside** its cluster lock as a backstop for
a job that was lost, which costs one indexed query per tick.

## Binding A — matchmaking accept

Only the middle of the flow changes; everything downstream is untouched.

```
sweep claims group ──▶ ReadyChecks.open(:matchmaking, tickets)   tickets: awaiting_accept
                                    │                            broadcast ready_check_started
                       all accepted │                            (deadline, player count, match_params)
                                    ▼
                        Match.create/1  ── as today ──▶  lobby, seats, lock, match_found
```

**Nothing is destroyed on failure, because nothing was built yet.** The check
runs *before* `Match.create/1`, so a dissolved match leaves no lobby, no chat
topic, no membership rows and no `after_lobby_create` / `after_lobby_join` hooks
fired for a match that never happened. The group dissolves along the seams
`Matchmaking` already has:

- accepters → `Matchmaking.requeue/1`. It leaves `queued_at` untouched, so they
  keep their place in the queue rather than being punished for someone else's
  dodge.
- decliners and timed-out players → `Matchmaking.discard/1` (cancelled, not
  requeued — the same treatment an unseatable player already gets).
- a **party** is matched as a unit, so it dissolves as one: any member
  declining cancels the whole party's tickets, consistent with `cancel/1`
  widening to the party and with `prune_offline/0`.

**Dodge penalties stay out of core.** The participants table records who
declined and who timed out; a game that wants a cooldown reads that in
`before_matchmaking_join` and refuses. Core supplies the record, the game rules
on the punishment — the same division as lobby states.

## Binding B — lobby ready

`POST /lobbies/ready_check` opens one over the current members. Authorization
copies `POST /lobbies/state` exactly: **the host of a host-managed lobby**;
**hostless** (matchmaking) lobbies belong to nobody, so only server-side code
and admins may open one there.

What the host may and may not do:

| | |
| --- | --- |
| Open one on demand ("Ready check!") | **Yes** — that is the whole endpoint |
| Cancel their own | **Yes** — `DELETE /lobbies/ready_check` |
| Re-open after a failed one | **Yes**, immediately |
| Start anyway, ignoring the result | **Yes** — core never gates state on a check (below) |
| Kick whoever stalled | **Yes** — the kick they already have |
| Answer *for* another player | **No** — a host who can mark you ready is not a ready check |

The host is a participant like everyone else, pre-marked `ready` at open time —
they clicked the button, that is their answer. **Bots and AI members cannot
press anything**, so plugins get a server-side `ReadyChecks.answer_for/3`
(RPC-blocked, like every server-authoritative call) to answer on behalf of a
member they own; the same function covers "auto-ready everyone in practice
mode".

Core does **not** gate `starting`/`playing` on a passing check — it does not
know when a game starts (lobby-state spec, "the vocabulary belongs to the
game"). The game wires the two together in five lines:

```elixir
def before_lobby_state_change(lobby, _from, "playing") do
  if ReadyChecks.passed?(lobby), do: {:ok, lobby}, else: {:error, :not_ready}
end

# The "all ready" callback: everyone answered yes.
def after_ready_check_passed(%{lobby_id: id}) when is_binary(id),
  do: Lobbies.transition_state(Lobbies.get_lobby(id), "starting")
```

A game that skips both hooks still gets a working ready check — it just means
nothing mechanically, which is the correct default for a game whose "start" is a
host button.

## If a game wants none of this

Most games will not use both bindings, and some will use neither. The cost of
ignoring it must be zero, so:

- **No check is ever opened by core.** Both tables stay empty; the lobby ready
  check only exists when a host asks for one, and matchmaking accept is behind
  a toggle that defaults off.
- **Lobby payloads do not change.** The open check is served by
  `GET /me/ready_check` and pushed on the lobby channel — never joined into
  `GET /lobbies`, which would cost a query per listed lobby for a feature most
  callers ignore.
- **`matchmaking_tickets` gains one nullable column** and one status value that
  is unreachable while the toggle is off. `match_found` keeps its exact
  payload and timing, so existing clients need no change.
- **Three optional hooks**, so plugins that ignore them keep compiling — that
  is what `@optional_callbacks` and `Hooks.Default` are for.
- **One indexed query per matchmaking tick** for the expiry backstop, on a
  partial index over pending checks — a scan of an empty index.

The one genuinely unavoidable cost is the migration and two more tables in the
schema docs.

## "Match status" — the third thing the issue asks for

No new concept; two existing fields, made complete and visible:

- **Queue side** — `matchmaking_tickets.status`:
  `queued → awaiting_accept → matched → (seated)`, or
  `cancelled`. Already returned by `GET /matchmaking/tickets/me`; the new status
  plus `ready_check_id` make the whole path legible to a client.
- **Match side** — `lobbies.state` (`created → starting → playing → ended`,
  game-extensible), which already ships.

## Web / realtime

One client-facing surface for both bindings — that is the point of the
generalization. A player is in at most one check, so it needs no id:

- `GET /me/ready_check` — the caller's open check, or `null`. For
  `kind: "ready"` it lists participants and their states (lobby members already
  see each other); for `kind: "accept"` it returns counts plus the caller's own
  state, so a pre-lobby check does not leak who you were paired with.
- `POST /me/ready_check` `{ready: true|false}` — the one verb. `409` when there
  is no open check, `422` when the check is not revocable.
- `POST /lobbies/ready_check` — host opens one (Binding B).
- No accept/decline endpoints on matchmaking: the check *is* the surface.

Events (user topic always; also the lobby topic for `kind: "ready"`, so a lobby
UI needs one listener): `ready_check_started`, `ready_check_updated` (someone
answered — counts only for `accept`), `ready_check_passed`,
`ready_check_failed {reason}`. Registered in `RealtimeEvents`, given protobuf
messages in `proto/` + `EventCodec` clauses, and handled in `GamendProto.gd`.
`match_found` keeps its exact meaning and payload, emitted after the check
passes.

## Hooks (per CONTRIBUTING §Hooks — six places each)

- `before_ready_check_open(subject, user_ids)` — veto (a game that wants no
  ready check in casual modes).
- `after_ready_check_passed(check)` — **the "all ready" callback**: everyone
  answered yes. Start the match, transition the lobby.
- `after_ready_check_failed(check, reason, participants)` — somebody declined or
  ran out the clock. Kick, re-open, record a dodge, notify.

Per-answer reactions are a **client** concern, so they get an event
(`ready_check_updated`) rather than a fourth hook — a server that wants to run
code on every individual toggle can do it in `respond/2`'s caller.

All dispatched after commit, never inside the lock.

## Admin / metrics

- Section on the matchmaking admin page: open checks, and pass / decline /
  timeout counts over 24 h — accept rate and dodge rate are the two numbers that
  tell you whether the queue is healthy. Force-cancel action, with API parity.
- Lobby detail page shows the open check and each member's state.
- PromEx counters for opened/passed/declined/timed-out plus a time-to-answer
  histogram.
- Retention: resolved checks pruned by the retention sweep
  (`RETENTION_READY_CHECKS_DAYS`, default 7); participants cascade.

## Compatibility

`matchmaking_accept_enabled` defaults to **false**. This is a genuine product
choice, not a compat shim: a casual mobile game should seat players instantly,
and a competitive one should not. With it off, matchmaking behaves exactly as
today. Binding B is additive — a game that never opens a check never sees one.

Polyglot then deletes `metadata["ready"]`, `set_ready/1`,
`set_ready_for_lobby/3` and `ensure_members_ready/3`, and calls core instead.

## Phasing

1. **Primitive + Binding B (lobby ready).** Smaller, touches no queue
   invariants, replaces a hack that exists in the wild today, and proves the
   `/me/ready_check` API in production.
2. **Binding A (matchmaking accept).** Ticket statuses, sweep changes, party
   dissolution — the riskier half, on machinery already exercised.

## Alternatives considered

- **Two narrow features instead of a primitive** — `accepted_at` on the ticket
  plus a `lobby_member_ready` table. Less machinery (the ticket already *is* a
  participant row), but two client APIs and two event families for one player
  gesture, and the deadline/resolution logic gets written twice. Rejected: the
  duplication lands in the client, where it is most expensive.
- **Lobby-first accept** — create the matchmaking lobby as today, run a check
  *inside* it, delete the lobby if it fails. Tempting: `lobby_id` stops being
  nullable, and the accept UI becomes the lobby UI with presence
  and chat already there. Rejected on the hook churn: every dissolved match
  would fire `after_lobby_create`, `before/after_lobby_join` per player and
  `after_lobby_leave` on the way out, so a game's quest counters, snapshots and
  analytics all count matches that never happened — and players would be seated
  (`users.lobby_id` set) while merely *deciding*. A pre-lobby check costs one
  nullable column and keeps "you are in a lobby" meaning exactly what it means
  today.
- **Ready flags in lobby `metadata`** (polyglot's shape, promoted to core).
  Rejected: read-modify-write, and `metadata` is client-writable by design.
- **Ready flags as `(user_id, lobby_id)` KV.** Tempting — the wipe-on-leave
  already exists — but there is no player-writable KV endpoint, and KV has no
  participant set, deadline or resolution.
- **Core gating lobby state transitions on a passing check.** Rejected: core
  does not own game semantics; `before_lobby_state_change` already does this.
- **Dodge cooldowns in core.** Deferred: core records, the game punishes.
- **Push notification on `ready_check_started`.** Deferred to a follow-up — a
  backgrounded mobile client cannot answer a 15-second popup it never saw, but
  push delivery latency makes that its own design question.

## Definition of done (CONTRIBUTING)

- [x] Migration adds both tables and the partial indexes; applies on SQLite
      **and** `GAMEND_DB_ADAPTER=postgres`. (`matchmaking_tickets.ready_check_id`
      lands with Phase 2, which is what needs it.)
- [x] No column added to `users`; no key added to `lobbies.metadata`; deleting a
      lobby cascades its checks and participants.
- [x] `serialize_lobby/2` is unchanged; `ready_check_updated` rides
      `ChannelUpdates`, `passed`/`failed` do not.
- [x] `ready_check: 11` registered in `AdvisoryLock` `@namespaces`;
      `respond/2` serializes write-then-evaluate.
- [x] `accept` fails fast and irrevocably; `ready` toggles and holds; join /
      leave / kick keep the participant set correct.
- [x] Simultaneous answers pass the check exactly once (the write-skew case).
- [x] Expiry job is idempotent and survives a restart; the sweep backstop runs
      outside the cluster lock.
- [ ] Matchmaking: accepters requeue with `queued_at` intact, decliners and
      timeouts are discarded, a party dissolves as a unit,
      `matchmaking_accept_enabled: false` reproduces today's behaviour exactly.
- [x] `POST /lobbies/ready_check` allows the host, rejects a non-host and
      **any** caller on a hostless lobby; the host cannot answer for a member,
      and `answer_for/3` is RPC-blocked.
- [x] A timed-out lobby check kicks nobody and moves no lobby state; kicking the
      straggler re-evaluates and can pass the check.
- [x] `/me/ready_check` hides co-players for `kind: "accept"`.
- [x] Three hooks in all six places, RPC-blocked, SDK-mirrored.
- [x] Four events registered in `RealtimeEvents`, with protobuf messages,
      `EventCodec` clauses and Godot addon handling.
- [x] Limits in `@limit_categories` and `.env.example`.
- [ ] `RETENTION_READY_CHECKS_DAYS` + retention sweep pruning resolved checks
      (folds into the in-flight Retention pass; checks cascade with their lobby
      today, so nothing is orphaned meanwhile).
- [x] Admin section + force-cancel + API parity + `admin_pages_render_test`.
- [x] Tests both adapters: concurrent responses, deadline expiry, kick-to-pass,
      and a booted run through open → toggle → pass and open → timeout.
- [ ] Phase 2 tests: decline-dissolves-party and a booted run through
      queue → accept → `match_found`.
- [x] Docs (Lobbies, Matchmaking, Data Schema), `api_spec.ex`, CHANGELOG, i18n.
- [x] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin warning-free.
