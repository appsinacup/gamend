# Locking that holds on SQLite too

Goal: make `GameServer.Lock.serialize/3` mean the same thing on both adapters —
*only one caller executes this critical section at a time* — so a plugin that
follows CONTRIBUTING ("any read-modify-write must hold a lock") is actually safe
on the default deployment.

Today it is a no-op on SQLite.

## The bug

[`GameServer.Repo.AdvisoryLock`](../../apps/game_server_core/lib/game_server/repo/advisory_lock.ex)
says:

> On SQLite, this is a no-op — SQLite serializes all writes at the database
> level, so advisory locks are unnecessary.

The premise is true and the conclusion does not follow. SQLite serializes each
**write**. It does not serialize a **read-modify-write spanning statements**,
which is the only thing anyone uses an advisory lock for:

```elixir
Lock.serialize(:wallet, user_id, fn ->
  balance = read_balance(user_id)          # both callers read 100
  write_balance(user_id, balance - 100)    # both write 0; one spend is free
end)
```

Ecto's SQLite transactions begin deferred: the read takes a shared lock and the
write tries to upgrade. Two overlapping transactions therefore either lose an
update or fail the upgrade with `SQLITE_BUSY` — which surfaces as an exception,
not a retry, because nothing re-runs the function body. On Postgres the same
code is correct. The two adapters silently disagree about the one guarantee the
API exists to provide.

This is not theoretical. Polyglot's own code review lists "per-user lock around
all coin/progress writes" as its **top priority finding** (double-spend), and it
fixed it by not using core's lock at all — `GameCommon.with_user_lock/2` wraps
`:global.trans` instead. A plugin author routing around the core primitive
because it does not work is the clearest possible signal.

The default deployment — embedded single-binary SQLite — is the one that is
wrong, and it is the one most users run.

## Fix

Keep the API. Change what the SQLite branch does.

```elixir
def serialize(namespace, resource_id, fun) do
  case Repo.adapter() do
    Ecto.Adapters.Postgres -> Repo.transaction(fn -> AdvisoryLock.lock(...); fun.() end)
    _                      -> Lock.Local.trans({namespace, resource_id}, fn ->
                                Repo.transaction(fun)
                              end)
  end
end
```

`GameServer.Lock.Local` is a keyed mutex built on `:global.trans/2` with the
requester slot set to `self()`:

```elixir
def trans(key, fun), do: :global.trans({{__MODULE__, key}, self()}, fun)
```

Two properties, both load-bearing, both learned from polyglot's bug report:

1. **The resource goes in the resource slot, the pid in the requester slot.**
   `:global` shares a lock between holders with the same *requester* id, so
   putting the user id there (polyglot's earlier bug) let two concurrent
   requests from the same user both acquire it — the exact case the lock
   exists for.
2. **`self()` makes it reentrant.** Nested `serialize/3` on the same key in one
   process succeeds instead of deadlocking, matching `pg_advisory_xact_lock`'s
   behaviour inside one transaction. Core has nested lock sites today
   (matchmaking sweep → match create), so this is required, not a nicety.

**Lock outside, transaction inside.** SQLite has one writer; holding the mutex
around the transaction keeps the transaction short and stops a queue of writers
from piling into `busy_timeout`. The Postgres path is unchanged because
`pg_advisory_xact_lock` must be inside its transaction to be released by it.

`:global.trans` works on a cluster too, so the SQLite path is not merely
"good enough for single node" — but SQLite deployments are single-node by
construction, so the common case is a local ETS-speed acquisition.

Also worth setting while we are here: `busy_timeout` on the SQLite connection
(Exqlite `:busy_timeout`, default is low) so an unlocked contended write waits
rather than raising. That is a backstop for code that forgets the lock, not a
substitute for it.

## What must not change

- **The API.** `serialize(namespace, resource_id, fun)` returning
  `{:ok, result} | {:error, reason}`. Every existing call site keeps working.
- **Postgres behaviour.** Byte-for-byte the same path.
- **Namespaces.** The `@namespaces` map and the string-hash offset stay; the
  local mutex keys on the same `{namespace, resource_id}` pair, so a Postgres →
  SQLite move cannot change which callers exclude each other.

## Documentation is half the fix

The moduledoc currently teaches the wrong thing. It should say, in order:

1. `serialize/3` is serialized on **both** adapters.
2. Any read-modify-write across statements needs it — including reads from KV,
   lobby metadata and user metadata, not just Ecto rows.
3. Inside a `Lobbies.Session` ([lobby-session.md](lobby-session.md)) gameplay is
   already serialized per lobby, but anything touching **value** (currency,
   inventory, quest rewards) still goes through the lock or through
   `Economy`'s atomic operations, because a netsplit can produce two sessions.
4. The lock is not a substitute for `Economy.debit/3`'s atomic
   `balance = balance - x where balance >= x`; prefer the atomic write where one
   exists.

Same text in the server-scripting docs page and the example plugin.

## Test that proves it

One test, run on **both** adapters, that fails today on SQLite:

```elixir
# 50 concurrent tasks each spend 1 coin from a 50-coin wallet via a
# read-modify-write inside Lock.serialize/3.
# Final balance must be 0 and no task may see a negative intermediate.
```

Plus a reentrancy test (nested `serialize/3` on the same key in one process
completes) and a cross-process fairness smoke test (N tasks, each observing
that no other task is inside the section — a shared ETS counter that must never
exceed 1).

## Alternatives considered

- **Document the limitation instead of fixing it** ("Postgres only"). Rejected:
  the default adapter would ship with a documented data-corruption footgun, and
  the CONTRIBUTING rule that tells plugin authors to use the lock would be
  false for most of them.
- **A dedicated lock GenServer / `Registry`-based mutex.** More code, one more
  supervised process, and single-node only — `:global.trans` already gives the
  same semantics with none of it.
- **`:atomics` / ETS spinlock.** Faster acquire, but no queueing, no fairness,
  no reentrancy, and a caller that dies holding it wedges the key.
  `:global.trans` releases on process death.
- **`BEGIN IMMEDIATE` for SQLite transactions.** Would turn lost updates into
  `SQLITE_BUSY` errors rather than silent corruption — better, but it makes
  every transaction take the write lock, and it still does not serialize the
  *function*, only the transaction. Worth doing as a separate hardening pass;
  it is not this fix.
- **Making `Lock.serialize/3` retry on conflict.** Retrying an arbitrary
  side-effecting closure is not safe in general; the lock avoids the conflict
  instead.

## Definition of done (CONTRIBUTING)

- [ ] `Lock.serialize/3` serializes on SQLite via `Lock.Local`; Postgres path
      unchanged; API and return shape identical.
- [ ] Requester slot is `self()`, resource slot is `{namespace, resource_id}`;
      nested acquisition in one process does not deadlock.
- [ ] Lock acquired outside the transaction on SQLite, inside on Postgres.
- [ ] `busy_timeout` set explicitly on the SQLite connection and documented.
- [ ] The 50-concurrent-spend test passes on SQLite **and**
      `GAMEND_DB_ADAPTER=postgres`; a reentrancy test and a mutual-exclusion
      test alongside it.
- [ ] Moduledoc, server-scripting docs page and example plugin state the
      both-adapters guarantee, the RMW rule, and the session/value distinction.
- [ ] CHANGELOG `[fixed]` entry naming the SQLite lost-update class explicitly —
      users need to know their existing plugin code was unprotected.
- [ ] Polyglot's `GameCommon.with_user_lock/2` can then delegate to
      `Lock.serialize(:user_econ, user_id, fun)` (tracked in that repo).
- [ ] `mix format`, `mix credo --strict`, full `mix test` green on both
      adapters.
