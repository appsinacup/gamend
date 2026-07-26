# Lobby session — one process per lobby, one writer per lobby

Goal: a supervised, cluster-unique process per lobby that a game runs its
gameplay mutations inside, so read-modify-write on lobby state is serialized by
construction instead of being re-invented (or forgotten) by every game.

Core owns the process, its lifetime and its supervision. It owns **no game
state** — the database stays the source of truth. What the session buys is a
single writer and a place to hang a timer.

## Why core

`GameServer.Lobbies.update_lobby/2` casts the whole `metadata` map. Any game
whose match state lives there is doing `read → compute → write` on a shared map
with no serialization, so two actions in the same tick lose one of them. There
is no seam in core that fixes this: `Lock.serialize/3` costs a DB round trip per
action and cannot hold a timer, and the plugin has nowhere to put a process
because supervision belongs to the host app.

The evidence is polyglot's `BoatGameServer` — a `:global`-registered GenServer
per lobby with an idle timeout, a self-call deadlock guard, a `run/2` escape
hatch and a `warn_if_unserialized_write` tripwire logging any write that took
the wrong path. That is 250 lines of pure infrastructure, written because core
offered none, and every action game on gamend will write it again.

Core already runs per-lobby processes — `Lobbies.SpectatorTracker` (ETS counts)
and `LobbySnapshots.Writer` — but neither is reachable by a plugin and neither
serializes anything a game does.

## What it is

`GameServer.Lobbies.Session` — a `GenServer` started on demand under a
`DynamicSupervisor`, registered `{:global, {:lobby_session, lobby_id}}` so at
most one exists cluster-wide.

```elixir
# Everything the game does to lobby state goes through this.
Session.run(lobby_id, fn ->
  lobby = Lobbies.get_lobby(lobby_id)
  state = advance(lobby.metadata["match"], action)
  Lobbies.update_lobby(lobby, %{metadata: %{"match" => state}})
end)
```

`run/3` executes the function **inside** the session process, so two concurrent
callers queue behind each other. Called from inside the session itself it runs
inline rather than deadlocking (polyglot's guard, promoted).

- `Session.run(lobby_id, fun, timeout \\ 15_000)` — serialized execution.
- `Session.whereis(lobby_id)` — pid or `nil`, no start.
- `Session.alive?(lobby_id)`.
- `Session.stop(lobby_id, reason)` — for a game that knows the match is over.
- `Session.send_after(lobby_id, msg, ms)` / `cancel_timer/2` — a timer owned by
  the session, delivered to the `handle_lobby_timer/2` hook.

Start is lazy: `run/3` starts the session if it is not up. The
`{:error, {:already_started, pid}}` race (two nodes starting at once) resolves
to the winner's pid — the same pattern `Matchmaking.Worker`'s moduledoc warns
about, handled once here instead of in every plugin.

## Why `:global` and not `Registry` / `:pg` / Horde

| | Cluster-unique | New dep | Survives netsplit |
| --- | --- | --- | --- |
| `Registry` | no — one per node | no | n/a |
| `:pg` | no — a group, not a name | no | n/a |
| `:global` | **yes** | no | merges, see below |
| Horde | yes | **yes** | CRDT handoff |

A per-node process defeats the purpose: two players on two nodes would get two
writers. `:global` gives cluster-wide uniqueness with no dependency, which is
what polyglot reached for unprompted. Horde would buy graceful handoff on node
loss at the cost of a dependency and a distributed CRDT that has to be
understood before it can be trusted — not worth it for a process that holds no
state.

**Netsplit honesty.** During a partition `:global` can register the same name on
both sides; on heal one is killed. So the session is a *serialization
optimization with a strong common case*, not a distributed-consensus guarantee.
That is exactly why it must not be the only thing protecting money:

> Anything that must never double-apply — currency, inventory, quest rewards —
> goes through `GameServer.Economy` / `Lock.serialize/3` **even inside a
> session**. The session serializes gameplay; the database serializes value.

This rule goes in the moduledoc, in the plugin docs and in the example plugin,
because the failure it prevents is silent.

## State, crashes and restarts

The session holds **no authoritative state**. Its state is `%{lobby_id, last_activity, timers}`
and a game-supplied scratch term that is explicitly documented as a cache: if
the process dies, the next `run/3` starts a fresh one and reads the lobby back
from the database. A game that keeps match state only in the process loses a
match to any crash, and core should not make that easy.

- **Idle timeout** — `GAMEND_LOBBY_SESSION_IDLE_MS` (default 30 min, polyglot's
  value),
  then `:hibernate` before shutdown so a long-lived quiet lobby costs a word or
  two of heap.
- **Lobby deleted** — the session subscribes to its own lobby topic and stops on
  `lobby_deleted`; retention's `reap_lobby/1` and `Lobbies.delete_lobby/1` need
  no change.
- **Crash** — `restart: :temporary`. A crashed session is not restarted; the
  next call starts a clean one. Restarting a process whose state is a cache
  buys nothing and hides bugs.
- **Mailbox** — `run/3` is a `GenServer.call` with a timeout; a slow game
  function backs up the queue for that lobby only. The admin page surfaces
  mailbox length so a wedged session is visible rather than mysterious.

## Timers

`PLAN_TIMERS` (polyglot) reaches the right conclusion: gameplay that can be
derived from timestamps should be, and a timer should be a *push* convenience,
not the mechanism. So core provides one timer per session, and documents the
constraint rather than the convenience:

- `Session.send_after/3` schedules; the message arrives in the session process
  and dispatches `handle_lobby_timer(lobby, msg)`.
- Timers are **best-effort**: they do not survive a session restart, a node
  loss or a deploy. A game whose state resolves only when a timer fires is
  broken; the same resolution must run on the next player action.
- Anything that must happen even if nothing else does is an **Oban job**
  (`GameServer.Jobs`), not a session timer. The moduledoc says so with an
  example of each.

## Hooks (CONTRIBUTING §Hooks — six places each)

- `after_lobby_session_start(lobby)` — warm a cache, seed a match, log.
- `handle_lobby_timer(lobby, msg)` — a scheduled message came due.
- `after_lobby_session_stop(lobby, reason)` — flush, persist a final snapshot.

All three optional, all RPC-blocked (a client cannot start a session or fire a
timer), all mirrored in the SDK.

## The tripwire

Polyglot's `warn_if_unserialized_write` is the reason its invariant held. Core
can do it properly: `Lobbies.update_lobby/2` checks, when
`GAMEND_LOBBY_SESSION_STRICT=true` (default on in dev/test, off in prod), whether a
session exists for that lobby and the caller is not it, and logs a warning with
the stacktrace. Off by default in production because the check costs a `:global`
lookup per update; on in dev because that is where the mistake is made.

## Admin

A section on the lobby detail page and a card on `/admin/lobbies`: live sessions
count, and per session the uptime, last activity, mailbox length, pending
timers, and a force-stop action with API parity. PromEx gauges for live sessions
and a histogram of `run/3` execution time — a game whose actions creep past a
few milliseconds is queueing its own players.

## What this is not

- **Not a game loop.** No tick, no fixed timestep. A game that wants one
  schedules a repeating `send_after` and accepts the best-effort contract.
- **Not authoritative storage.** See above; the DB is.
- **Not required.** A turn-based game that writes once per turn under
  `Lock.serialize/3` never needs a session, and pays nothing: sessions only
  exist when a game calls `run/3`.

## Alternatives considered

- **`Lock.serialize/3` for every action.** Correct (once the SQLite hole in
  [locking.md](locking.md) is closed) but a transaction and a lock round trip
  per input, and no home for timers or per-lobby caches. Keep it as the
  value-safety primitive; the session is the throughput one.
- **`:global.trans` per call** (polyglot's other pattern, used for per-user
  economy). Serializes without a process, so no timers, no idle lifecycle, no
  place for the tripwire, and a lock round trip per action.
- **One process per *match* rather than per lobby.** A lobby can host several
  matches in sequence; keying on the lobby means the process outlives a match
  and its scratch cache survives a rematch. A game that wants strict per-match
  isolation calls `stop/2` at match end.
- **Making core's existing `LobbySnapshots.Writer` the session.** It is a
  per-lobby process already, but it is a write-behind buffer with its own
  lifetime tied to snapshotting; overloading it would couple an opt-in feature
  to the gameplay path.

## Definition of done (CONTRIBUTING)

- [ ] `GameServer.Lobbies.Session` + `Session.Supervisor` under
      `host_supervision.ex`, `restart: :temporary`, idle timeout configurable.
- [ ] `run/3` serializes concurrent callers, runs inline when called from
      within the session, and resolves the `:already_started` start race.
- [ ] A session stops on lobby delete, on idle, and on `stop/2`; a crash loses
      no persisted state (test kills the process mid-match and replays).
- [ ] Timers deliver to `handle_lobby_timer/2`, do not survive restart, and the
      docs show the Oban alternative for must-run work.
- [ ] Three hooks in all six places, RPC-blocked, SDK-mirrored.
- [ ] `GAMEND_LOBBY_SESSION_STRICT` tripwire warns on out-of-session
      `update_lobby/2`; off in prod, on in dev/test.
- [ ] `session_idle_ms`, `session_call_timeout_ms` and `session_strict`
      declared on the `:lobby` settings provider (names derive to
      `GAMEND_LOBBY_SESSION_*`); `.env.example` regenerated with
      `mix gamend.settings.env_example`.
- [ ] Admin section (live sessions, mailbox, timers, force-stop) + API parity +
      `admin_pages_render_test`; PromEx gauge + histogram.
- [ ] Docs: server-scripting page gets a "one writer per lobby" section stating
      the money rule; `api_spec.ex`, CHANGELOG, i18n.
- [ ] Tests on both adapters: two concurrent `run/3` calls serialize, a
      cross-node start yields one process, idle shutdown fires, lobby delete
      stops it, timer fires once and is not resurrected by a restart.
- [ ] Polyglot's `BoatGameServer` reduces to `Session.run/3` calls (tracked in
      the polyglot repo, not here).
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
