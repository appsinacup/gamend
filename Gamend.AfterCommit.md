# `Gamend.AfterCommit`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/after_commit.ex#L1)

Side effects that wait for the enclosing transaction to commit.

A broadcast, a hook dispatch or a spawned task inside a transaction runs
while the transaction holds the database, which on SQLite (a single
connection, `BEGIN IMMEDIATE`) is every other request's database too. It is
also observed before the write is visible, and survives a rollback of the
write it announces. `defer/1` queues the effect instead, and the queue runs
once the outermost `transaction/2` (or `Gamend.Lock.serialize/3`) has
committed and released its lock. A rollback or an exception drops it.

Outside such a scope `defer/1` runs the effect at once, so a helper can
always defer and stay correct whether or not its caller holds a
transaction. Inside a transaction opened with a bare `Repo.transaction/2`
there is no commit to wait for, and it also runs at once, as before.

Queued effects run in order, in the calling process, after the lock is
released. The write is committed by then, so one that raises or exits is
logged and does not stop the rest or fail the caller. An effect run at once
behaves as a plain call.

# `collect`

```elixir
@spec collect((-&gt; result)) :: result when result: term()
```

Runs `body`, which opens a transaction, as the scope `defer/1` queues into:
the queue runs when `body` returns `{:ok, _}` and is dropped otherwise. For
wrappers that take a lock around the transaction (`Gamend.Lock.serialize/3`),
so the effects run after the lock is released as well.

Inside an outer scope it only runs `body`; the outer scope decides.

# `defer`

```elixir
@spec defer((-&gt; any())) :: :ok
```

Runs `fun` once the enclosing scope commits, or now when there is none.

# `deferring?`

```elixir
@spec deferring?() :: boolean()
```

Whether `defer/1` would queue rather than run.

# `transact`

```elixir
@spec transact((-&gt; {:ok, term()} | {:error, term()}), keyword()) ::
  {:ok, term()} | {:error, term()}
```

`Repo.transact/2`, with `defer/1` inside it queued until it commits.

# `transaction`

```elixir
@spec transaction((-&gt; term()) | Ecto.Multi.t(), keyword()) ::
  {:ok, term()} | {:error, term()} | {:error, term(), term(), map()}
```

`Repo.transaction/2` (a function or an `Ecto.Multi`), with `defer/1` inside
it queued until it commits. Every transaction in core goes through here.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
