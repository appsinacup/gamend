# `Gamend.TestSupport.Race`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/test_support/race.ex#L1)

Releases racers at the same instant, each on its own database connection,
so a test can show whether a rule holds when requests land together.

For tests only. It lives in `lib/` rather than core's `test/support` so a
host app can use it from its own case template: a dependency's test
support is not compiled into a host. Core's suite uses it through
`Gamend.RaceCase`; a host's case calls `race/1,2` and `unboxed/1` and
deletes what it made in `on_exit/1`.

The sandbox runs a whole test on one connection, so calls made at once from
several processes still reach the database one statement at a time, and a
check-then-write bug passes on every adapter. Here each racer runs outside
the sandbox (`Ecto.Adapters.SQL.Sandbox.unboxed_run/2`), in its own
transactions, and what it writes is committed. The races overlap only on
Postgres. SQLite runs one write transaction at a time, so there the racers
run one after another: released together they only queued for the pool's
one connection, and on a loaded machine a long wait in that queue dropped a
racer (`DBConnection.ConnectionError`) for nothing the code under test did.

A racer that raises comes back as `{:raised, exception}` instead of failing
the test from another process, so a test can assert nothing raised: an
exception there is a 500 for a client.

# `race`

```elixir
@spec race([(-&gt; term())]) :: [term()]
```

Runs each function in `funs` as one racer, all released at once. Answers
their results in order, a raise as `{:raised, exception}`.

# `race`

```elixir
@spec race(pos_integer(), (pos_integer() -&gt; result)) :: [
  result | {:raised, Exception.t()}
]
when result: term()
```

Runs `count` racers, `fun.(1)` to `fun.(count)`, all released at once.
Answers their results in order, a raise as `{:raised, exception}`.

# `unboxed`

```elixir
@spec unboxed((-&gt; result)) :: result when result: term()
```

Runs `fun` on a connection of its own, outside the sandbox. What it writes
is committed.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
