# `Gamend.Retention`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/retention.ex#L1)

Periodically prunes old rows from unbounded tables.

Retention is configured per table via `Gamend.Settings` (group `:retention`,
env vars `GAMEND_RETENTION_*`); `0` or unset keeps data forever:

- `GAMEND_RETENTION_CHAT_MESSAGES_DAYS` — `chat_messages` older than N days
- `GAMEND_RETENTION_NOTIFICATIONS_DAYS` — `notifications` older than N days
- `GAMEND_RETENTION_PAYMENT_EVENTS_DAYS` — payment provider webhook events older
  than N days (purchases/entitlements are never pruned)
- `GAMEND_RETENTION_LOBBY_SNAPSHOTS_DAYS` — lobby snapshots, events and their
  content blobs. Unlike the others this defaults to 30 rather than "keep
  forever": snapshots hold user metadata, and the window is what bounds that
  exposure. Runs flagged anomalous keep
  `GAMEND_RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` instead (default 90).
- Client log sessions (`Gamend.ClientLogs`), on their own settings rather
  than a `GAMEND_RETENTION_*` var: `retention_days` (14) and
  `retention_flagged_days` (90), keyed off `last_seen_at`. This prunes the
  index over client logs, not the lines — those live in the host's log store
  on its own retention.
- `GAMEND_RETENTION_PUSH_TOKENS_DAYS` — push tokens untouched (registered, used,
  or disabled) for N days. Defaults to 270 — Google's stale-token guidance
  — so the table tracks live devices, not install history.
- `GAMEND_RETENTION_INVITES_DAYS` — resolved group/party invites and join requests,
  N days after resolution (default 30). Pending rows are never pruned.
- `GAMEND_RETENTION_MATCHMAKING_TICKETS_HOURS` — tickets older than N hours
  (default 24), in any status.
- `GAMEND_RETENTION_TOURNAMENTS_DAYS` / `GAMEND_RETENTION_LEDGER_DAYS` — finished
  tournaments and the wallet/inventory ledgers. Both default to `0`: they
  are history an operator may be required to keep.
- `GAMEND_RETENTION_ACTIVITY_DAYS` — `user_activity_days` rows (one per user per
  UTC day seen, behind DAU and D1/D7/D30) older than N days. Defaults to
  `0`; the table grows by at most one row per active user per day, and a
  window shorter than the analytics cohort span (60 days) blanks the
  retention numbers.
- `GAMEND_RETENTION_ANONYMOUS_USERS_DAYS` (90) — device-only accounts inactive
  for N days. `GAMEND_RETENTION_UNCONFIRMED_USERS_DAYS` (30) — email accounts
  whose address was never confirmed, inactive for N days.
- `GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES` (15) — lobbies nobody has been seen in
  for N minutes, in minutes rather than days. The same window releases a lobby
  seat held by a long-offline player. A party everyone abandoned is disbanded
  on its own window, `GAMEND_RETENTION_ABANDONED_PARTY_MINUTES` (15).

Expired IP bans, OAuth sessions older than a day, user tokens past their own
context's validity, and stored avatars whose owner no longer exists are always
removed (independent of the env vars above). Deletes are idempotent, so
running on several instances at once is harmless; each class is batched and
failure-isolated, and emits `[:gamend, :retention, :pruned]` telemetry with
its count.

## Classes a host or plugin adds

A host application and a plugin have tables of their own, and the rule that
an unbounded table needs a retention class applies to them too. Register one
and it runs, is failure-isolated, and emits telemetry exactly like core's:

    Gamend.Retention.register_class(:forge_builds, &Forge.Builds.prune/0)

The function takes no arguments and answers how many rows it deleted.
Registering the same name twice replaces the first, so a module can call this
at every boot without accumulating duplicates.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `prune_all`

```elixir
@spec prune_all() :: %{required(atom()) =&gt; non_neg_integer()}
```

Runs all configured pruning steps once. Returns a map of deleted row
counts per table.

# `register_class`

```elixir
@spec register_class(atom(), (-&gt; non_neg_integer())) :: :ok
```

Register a pruning class owned by a host application or a plugin.

Core's own classes are a fixed list in `prune_all/0`, which left a host with
no way to bound its own tables: `CONTRIBUTING.md` requires every unbounded
table to have a class or a stated reason it is bounded, and a fork could not
comply. Registering by name rather than appending means a module can call
this on every boot — the second registration replaces the first instead of
pruning twice.

# `registered_classes`

```elixir
@spec registered_classes() :: %{required(atom()) =&gt; (-&gt; non_neg_integer())}
```

Classes registered on top of core's own.

# `run_now`

```elixir
@spec run_now() :: %{required(atom()) =&gt; non_neg_integer()}
```

Sweeps now instead of waiting for the next cycle, and records the run like a
scheduled one. Runs inside the GenServer so a manual run and the timer can
never overlap.

# `start_link`

# `status`

```elixir
@spec status() :: %{
  last_run_at: DateTime.t() | nil,
  duration_ms: non_neg_integer() | nil,
  results: %{required(atom()) =&gt; non_neg_integer()}
}
```

What the last sweep did, for the admin page. Falls back to "never run" when
the sweeper is not supervised (tests, or an instance with it disabled).

# `unregister_class`

```elixir
@spec unregister_class(atom()) :: :ok
```

Undoes `register_class/2`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
