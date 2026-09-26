# `Gamend.Accounts.StalePresenceSweeper`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/stale_presence_sweeper.ex#L1)

Periodically sweeps users whose `is_online` flag is `true` but whose
`last_seen_at` timestamp is older than a configurable threshold.

This is a safety net for node crashes or ungraceful disconnects where the
`UserChannel.terminate/2` callback never fires. Without this, users would
remain marked as online indefinitely.

## Configuration

`interval_ms` and `stale_threshold_s` are settings (`GAMEND_PRESENCE_*`).
`enabled: false` in the app config turns the sweep off entirely (tests).

A connected socket refreshes `last_seen_at` on a heartbeat derived from the
threshold (`heartbeat_ms/0`), so a live player is never swept.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `config`

```elixir
@spec config() :: keyword()
```

Returns the current configuration used by the sweeper.

# `heartbeat_ms`

```elixir
@spec heartbeat_ms() :: pos_integer()
```

How often a connected socket refreshes `last_seen_at`: three fifths of
`stale_threshold_s`, so two refreshes fit before a user reads as stale, and
never less often than every 3 minutes.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
