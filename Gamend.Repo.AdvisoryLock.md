# `Gamend.Repo.AdvisoryLock`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/repo/advisory_lock.ex#L1)

Advisory locking for protecting TOCTOU (Time-of-Check-Time-of-Use) patterns.

On PostgreSQL, acquires a transaction-scoped advisory lock via
`pg_advisory_xact_lock(namespace, resource_id)`. The lock is automatically
released when the enclosing `Repo.transaction` commits or rolls back.

On SQLite, this function is a no-op, because SQLite has no advisory locks.
That is a fact about *this function*, not a claim that locking is unnecessary
there: SQLite serializes each write, which is not the same as serializing a
read-modify-write spanning statements, and does nothing at all for a critical
section held over ETS or process state.

Callers should not use this module directly for that reason. Go through
`Gamend.Lock.serialize/3`, which picks this on Postgres and a keyed
`:global` mutex (`Gamend.Lock.Local`) everywhere else, so the guarantee
holds on both adapters.

## Usage

Always call within a `Repo.transaction`:

    Repo.transaction(fn ->
      AdvisoryLock.lock(:lobby, lobby.id)
      count = count_members(lobby.id)
      if count >= lobby.max_users, do: Repo.rollback(:full)
      do_join(...)
    end)

## Namespaces

Each resource type uses a distinct integer namespace to avoid collisions:

- `:lobby` → 1
- `:group` → 2
- `:party` → 3
- `:friendship` → 4

You can also pass an arbitrary string as the namespace. The string is
hashed to a stable 32-bit integer via `:erlang.phash2/2`, so any
string (e.g. `"word_guessed"`, `"my_rpc"`) works without pre-registration.

## Examples

    # Atom namespace (predefined):
    AdvisoryLock.lock(:lobby, lobby_id)

    # String namespace (ad-hoc):
    AdvisoryLock.lock("word_guessed", lobby_id)

# `lock`

```elixir
@spec lock(atom() | String.t(), String.t()) :: :ok
```

Acquire a transaction-scoped advisory lock for the given resource.

`namespace` can be a predefined atom (`:lobby`, `:group`, `:party`) or any
arbitrary string. `resource_id` is a UUID string; it is hashed to a stable
32-bit integer for `pg_advisory_xact_lock` (a hash collision only causes
extra serialization, never lost mutual exclusion).

Must be called inside a `Repo.transaction`. On PostgreSQL, blocks until
the lock is available. On SQLite, returns immediately — see the moduledoc.

# `namespace_id`

```elixir
@spec namespace_id(atom() | String.t()) :: non_neg_integer()
```

The integer namespace `pg_advisory_xact_lock` is called with.

Public so `Gamend.Lock.serialize/3` can resolve it on *every* adapter, not
only Postgres. An unregistered atom is a programming error, and it used to
surface as a `KeyError` from deep inside the Postgres branch — while the
SQLite branch never calls `lock/2` at all and so never noticed. Anyone
developing on the default SQLite setup could therefore add a lock with an
unregistered namespace, watch every local test pass, and only find out on the
Postgres CI job.

# `namespaces`

The registered lock namespaces and their ids (for introspection).

# `postgres?`

```elixir
@spec postgres?() :: boolean()
```

Returns true if the Repo was compiled with the PostgreSQL adapter.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
