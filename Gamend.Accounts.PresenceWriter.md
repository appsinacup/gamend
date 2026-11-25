# `Gamend.Accounts.PresenceWriter`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/presence_writer.ex#L1)

Coalesces `users.is_online` transitions into one write per flush window.

`Accounts.set_user_online/1` and `set_user_offline/1` already skip the write
entirely when the flag is unchanged, so a reconnect or a second socket for an
already-online player costs nothing. What is left is the storm: N *distinct*
players connecting at once is N separate transactions, and on single-writer
SQLite those serialize behind each other.

This buffers the transitions and flushes them as one `SELECT` (which rows
would actually change) plus one `UPDATE` per direction, then fires the same
cache invalidation, broadcasts and hooks the synchronous path fires — once
per user that really transitioned, never for a no-op.

## Buffered state is in ETS, not in the GenServer

Callers have to read the buffer to decide whether they are making a real
transition: a player who disconnects inside the flush window must see their
own pending connect, or the disconnect reads as a no-op and the stale connect
is what reaches the database. Routing that read through the process would put
a `GenServer.call` on every socket join — the exact serialization this module
exists to remove — so the buffer is a public ETS table and the process only
owns the timer.

## Configuration

    config :gamend_core, Gamend.Accounts.PresenceWriter,
      flush_ms: 200      # 0 writes through synchronously

`flush_ms: 0` writes each change as it comes and is what the test environment
runs, so a test can assert on `is_online` immediately after the call. In
production the flag lags by at most one window — `StalePresenceSweeper` is
the backstop that already tolerates far more drift than that, and realtime
subscribers are told over PubSub from the channel, not from this write.

If the process is not running (some test setups start a partial tree),
`flush_ms/0` reports 0 and callers write through rather than dropping the
transition on the floor.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `flush`

```elixir
@spec flush() :: :ok
```

Flushes everything buffered right now. Synchronous; used by tests.

# `flush_ms`

```elixir
@spec flush_ms() :: non_neg_integer()
```

Milliseconds to buffer transitions. 0 means callers write through.

# `mark`

```elixir
@spec mark(Ecto.UUID.t(), boolean()) :: :ok
```

Queues an online/offline transition for `user_id`.

Later marks for the same user replace earlier ones, so a connect immediately
followed by a disconnect flushes once, as the disconnect.

# `pending`

```elixir
@spec pending(Ecto.UUID.t(), boolean()) :: boolean()
```

The state this user is buffered to become, or `default` when nothing is
buffered for them.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
