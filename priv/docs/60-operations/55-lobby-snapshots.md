---
icon: hero-camera
---

# Lobby Snapshots

Lobby snapshots are a durable record of how a [lobby's](/docs/lobbies) state evolved during a run, captured at every mutation chokepoint and browsable at [/admin/lobby_snapshots](/admin/lobby_snapshots). A timeline reads `snapshot -> [events] -> snapshot`: snapshots record *what* changed, events record *why*. The whole system is off by default. Turning it on is a privacy decision, because snapshots embed user metadata and KV.

## Turning it on

```elixir
GAMEND_LOBBY_SNAPSHOTS_ENABLED=true
```

Two more settings bound what user-scoped data a snapshot may contain: `GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS` lists the user-scoped KV keys to capture (empty by default, which captures **none**, since user KV is the widest privacy exposure in a snapshot), and `GAMEND_LOBBY_SNAPSHOTS_MAX_KV_ENTRIES` (default 200) caps KV entries per snapshot.

## What is captured, and when

Each snapshot stores the lobby row's fields, the lobby metadata, the members (ids, metadata and online flag only, never username or email, because account deletion cannot reach data embedded in JSON, so the way to keep a deleted user's details out of snapshots is to never store them), the lobby-scoped KV, and whichever user-scoped KV keys you allowlisted. Every section is content-hashed and stored once, so an unchanged section across a hundred snapshots costs one blob.

Captures fire at three kinds of moment:

- **After every hook call.** The snapshot is taken against the hook caller's current lobby and attributed `hook:<name>`. Since externally-driven hooks like `after_user_offline` go through the same path, a player dropping offline mid-run leaves a snapshot too.
- **At lobby teardown** (`lobby:deleted`, `lobby:emptied`), gathered synchronously because the state is about to disappear.
- **Wherever your plugin says so**, at its own chokepoints:

```elixir
# Capture now, attributing the mutation
Gamend.LobbySnapshots.capture_lobby(lobby_id, "timer:scheduled_collision", user_id: user.id)

# Record *why* a decision happened within the current interval
Gamend.LobbySnapshots.record_event(lobby_id, "speed_reduced", %{"gap" => gap})

# Report a write that happened somewhere capture cannot see
Gamend.LobbySnapshots.record_coverage_gap(lobby_id, "unserialized_write", %{"key" => key})
```

`record_event/4` is what makes timelines explain themselves: a snapshot can show `speed: 100 -> 50`, but only an event carries the gap that caused it. `record_coverage_gap/3` is the system reporting its own blind spots: a mutation detected outside the chokepoints is by definition missing from the snapshots, and the admin page counts these per run.

## Anomaly flagging

A hook that returns `{:error, _}` flags its capture automatically (a failed hook is the case most worth having a record of), and `capture_lobby/3` accepts `flagged: true` for your own error paths. A run is flagged if *any* of its snapshots is. Flagged runs wear a badge in the admin listing, can be filtered to with one click, and keep the longer retention window below.

## The admin page

[/admin/lobby_snapshots](/admin/lobby_snapshots) lists runs newest first, with snapshot counts, flagged badges and the coverage-gap tally. Opening a run shows its timeline; expanding a snapshot computes the field-level diff against the previous one (`%{section => [%{path, from, to}]}`, with paths flattened so a value buried three maps deep reads as one row) alongside the fully reconstructed state as raw JSON. A text filter searches everything at once: diff paths, values and events. That diff is the point of the whole system: a value that reverts between snapshots should be visible at a glance rather than reconstructed by hand.

The same reads are available to plugins: `timeline/1`, `state_at/1`, `diff/2`, and `gather_sections/1` for the live view of a lobby that capture would record.

## Retention

`GAMEND_RETENTION_LOBBY_SNAPSHOTS_DAYS` defaults to **30** (unlike most retention vars, which default to keep-forever) because retention is what actually bounds the privacy exposure of captured metadata and KV. Runs flagged anomalous keep `GAMEND_RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` instead (default 90, never shorter than the normal window). Snapshots and events expire together, per run: a flagged run keeps its events too.

## What it costs

When disabled, every call site pays a single `Application.get_env`, so leaving capture calls in hot paths is fine. When enabled, gathering runs off the caller's process, section hashing happens on the calling side rather than in the shared writer, and writes are batched through a single writer process so a database round trip never shows up as gameplay stutter; teardown captures are the one synchronous case. Enable it when you are chasing how a lobby got into a bad state. The default-off setting exists because of what snapshots contain, not what they cost.

## Reference

- **Elixir API:** [`Gamend.LobbySnapshots`](https://docs.gamend.org/Gamend.LobbySnapshots.html) - capture, events and reads, with their signatures and docs.
- **Admin:** [/admin/lobby_snapshots](/admin/lobby_snapshots) - timelines, diffs and coverage gaps on your server.
- **Settings:** the `Lobby snapshots` and `Retention` groups in the [Settings](/docs/settings) guide.
- **Hooks:** [Server scripting](/docs/server-scripting) - the callbacks whose completions drive automatic capture.
- **Lobbies:** [Lobbies](/docs/lobbies) - the lifecycle these runs record.
