# `Gamend.LobbySnapshots`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/lobby_snapshots.ex#L1)

Durable record of how a lobby's state evolved during a run.

A lobby *is* a run — each level quick-joins a fresh lobby — so `lobby_id` is
the correlation key and needs no separate id. A timeline reads
`snapshot N -> [events] -> snapshot N+1`: snapshots record *what* changed,
events record *why*.

Two entry points, both cheap for callers:

- `capture_lobby/3` at a mutation entry point (hook completion, game-loop
  message, lobby teardown).
- `record_event/4` where a decision is worth explaining.

Both enqueue into `Gamend.LobbySnapshots.Writer` rather than writing
inline — call sites live in the serialized game loop, where a DB round trip
shows up as gameplay stutter.

Disabled by default; see `enabled?/0`.

# `capture_hook`

```elixir
@spec capture_hook(atom() | String.t(), term(), term()) :: :ok
```

Capture after a hook completed, attributing it to the hook's caller.

Core cannot read a lobby out of a hook's arguments — they are plugin-defined —
and the only context it injects is the caller. So this resolves the caller's
*current* lobby and captures against that, skipping entirely when the caller
is absent or not in one. A hook that mutates lobby state on behalf of someone
outside it is invisible here and needs `capture_lobby/3` at its own chokepoint.

Everything including the caller lookup happens off the hook's process, so a
hook call pays one `Application.get_env` when capture is disabled and one task
spawn when it is on.

# `capture_lobby`

```elixir
@spec capture_lobby(String.t(), String.t(), keyword()) :: :ok
```

Capture the current state of a lobby, attributing it to `trigger`.

`trigger` names what caused the mutation — `"hook:finish_boat_game"`,
`"timer:scheduled_collision"`, `"lobby:deleted"`. Options:

- `:sync` — gather inline instead of off the caller's process. Required when
  the state is about to disappear (lobby teardown), where an async gather
  would race the delete and capture nothing.
- `:flagged` — mark the run as anomalous, exempting it from the default
  retention sweep. Set this when the mutation errored.
- `:user_id` — attribution for the mutation.

Returns `:ok` regardless; capture must never fail a caller's real work.

# `coverage_gap?`

```elixir
@spec coverage_gap?(Gamend.LobbySnapshots.Event.t() | String.t()) :: boolean()
```

Whether an event kind marks a coverage gap rather than a game decision.

# `diff`

```elixir
@spec diff(Gamend.LobbySnapshots.Snapshot.t(), Gamend.LobbySnapshots.Snapshot.t()) ::
  %{
    required(String.t()) =&gt; [map()]
  }
```

Field-level differences between two snapshots' state.

Returns `%{section => [%{path: ["a", "b"], from: term, to: term}]}`, with
unchanged sections omitted entirely. Paths are flattened, so a field buried in
nested maps reads as `["boat_adventure", "effects", "speed_reduced"]` rather
than requiring the reader to walk two nested objects to spot it.

This is the point of the whole system: a value that reverts between snapshots
should be visible at a glance rather than reconstructed by hand.

# `enabled?`

```elixir
@spec enabled?() :: boolean()
```

Whether capture is currently on.

Checked before any gathering work, so leaving call sites in hot paths costs a
single `Application.get_env` when off.

# `gather_sections`

```elixir
@spec gather_sections(String.t()) :: %{required(String.t()) =&gt; map() | list()}
```

Read every section of a lobby's current state, as raw (unhashed) content.

Public so plugins can reuse the same view of a lobby that capture records.

# `list_coverage_gaps`

```elixir
@spec list_coverage_gaps(keyword()) :: [Gamend.LobbySnapshots.Event.t()]
```

Coverage gaps across all lobbies, newest first.

# `list_events`

```elixir
@spec list_events(String.t()) :: [Gamend.LobbySnapshots.Event.t()]
```

Events for a lobby, oldest first.

# `list_lobbies`

```elixir
@spec list_lobbies(keyword()) :: [map()]
```

Distinct lobbies that have snapshots, newest first.

The lobby row is usually gone by the time anyone reads this, so the listing is
built from the snapshots themselves rather than joined against `lobbies`.

# `list_snapshots`

```elixir
@spec list_snapshots(String.t()) :: [Gamend.LobbySnapshots.Snapshot.t()]
```

Snapshots for a lobby, oldest first.

# `load_blobs`

```elixir
@spec load_blobs([String.t()]) :: %{required(String.t()) =&gt; map() | list()}
```

Load blob content for a list of hashes, as a hash => content map.

# `prepare`

```elixir
@spec prepare(String.t(), String.t(), keyword()) :: map() | nil
```

Gathers a capture now without recording it; `record/1` records it later.

For a caller that must read the state before a transaction unwinds it, and
outside that transaction, but records it only if the transaction commits
(the last member leaving deletes the lobby). `nil` when snapshots are off or
there is nothing to read. Takes `capture_lobby/3`'s options but `:sync`.

# `record`

```elixir
@spec record(map() | nil) :: :ok
```

Records a capture `prepare/3` gathered. `nil` records nothing.

# `record_coverage_gap`

```elixir
@spec record_coverage_gap(String.t(), String.t(), map()) :: :ok
```

Record that a mutation happened somewhere capture cannot see.

A plugin calls this from a tripwire that detects state being written outside
the chokepoints capture hangs off — a host's `warn_if_unserialized_write/1`
is the first. Such a write is *by definition* a mutation missing from the
snapshots, so this is the system reporting its own blind spots.

Stored as an ordinary event, deliberately: a gap is most useful read in the
timeline where it happened, next to the snapshots that are consequently
incomplete. The admin view also lists them across lobbies.

# `record_event`

```elixir
@spec record_event(String.t(), String.t(), map(), keyword()) :: :ok
```

Record a decision that happened within the current snapshot interval.

`payload` carries the fields that explain the decision — a snapshot can show
`speed: 100 -> 50`, but only an event carries the `gap` that caused it.

# `resolved_config`

```elixir
@spec resolved_config(atom(), term()) :: term()
```

The resolved value of a config key, for tests and diagnostics.

Exposed so resolution can be asserted against the real code path rather than
a copy of it.

# `state_at`

```elixir
@spec state_at(Gamend.LobbySnapshots.Snapshot.t()) :: %{
  required(String.t()) =&gt; term()
}
```

Reconstruct full state as of a given snapshot.

For each section, take the latest occurrence at or before that snapshot.
Sections are stored whole, so this is a lookup — never a merge.

# `timeline`

```elixir
@spec timeline(String.t()) :: %{
  prologue: [Gamend.LobbySnapshots.Event.t()],
  intervals: [map()]
}
```

A lobby's snapshots in order, each with the events that followed it.

Reads as `snapshot -> [events] -> snapshot -> [events]`. An event belongs to
the interval opened by the latest snapshot at or before it; events preceding
the first snapshot land in `:prologue`.

`index` is a 1-based display number derived here rather than stored — nothing
has to hand out sequence numbers at write time for this to be stable.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
