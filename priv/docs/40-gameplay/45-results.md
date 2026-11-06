---
icon: hero-list-bullet
---

# Results

A result is what happened in one play: one row per play per player, and the events of that play in the order they happened. The game writes an event when something happens, and that is all it writes. There is no summary to keep up to date and no second copy of the play's state: the [lobby](/docs/lobbies) holds the live state while the play runs, and the result is the record it leaves.

The same rows answer three questions:

- **What happened, in order:** the events by id, which is a replay.
- **How it went, at a glance:** each event key's count and sum, computed by one query.
- **What a player has played:** their results, newest first, filtered by kind.

## The rows

`results`, one row per play per player:

| Field | Means |
|---|---|
| `id` | The play. |
| `user_id` | The player. A result is deleted with its account. |
| `lobby_id` | The lobby the play ran in, or `""`. A plain id, not a key: the lobby is gone long before its result is. |
| `kind` | What was played, a word the game picks: `match`, `boat_run`, `test`. |
| `visibility` | Who may read it, in KV's words (below). |
| `status` | `open` while the play runs, `ended` once it is over. |
| `metadata` | What the play was, set when it starts: the settings, the language. Never its outcome, which is the events'. |
| `started_at`, `ended_at` | When it began, and ended (`null` while open). |

`result_events`, what happened:

| Field | Means |
|---|---|
| `id` | The event, and its place: ids are UUIDv7, strictly ordered on a node, so sorting by `id` is the order the events were written in. |
| `result_id` | The play it belongs to. |
| `elapsed_ms` | Milliseconds since the play's `started_at`, on the server's clock. |
| `key` | What happened: `deal`, `answer`, `hint`, `skip`. |
| `value` | The number it carries, or `null`: `1` right and `0` wrong, `10` coins, `2.6` km. |
| `metadata` | A small map when the key needs more: the question, the option picked, the seed. |

## Writing

Only server code writes results: a plugin, the host app, a hook handling a player's move. A client never writes one.

```elixir
{:ok, result} =
  Gamend.Results.start(user.id, "match",
    lobby_id: lobby.id,
    visibility: :owner_only,
    metadata: %{"lang" => "fr", "questions" => 10}
  )

Gamend.Results.record(result, "deal", nil, %{"seed" => seed})
Gamend.Results.record(result, "answer", 1, %{"question" => "q1"})
Gamend.Results.record(result, "hint", 10)

{:ok, result} = Gamend.Results.finish(result)
```

An event is one insert, and `finish/1` one update that only matches an open row, so a play ends once however many places try to end it; the second answers `{:error, :already_ended}`. The two take turns under the result's lock: an event is written before the end or answers `{:error, :ended}`, even through a result struct read while it was still open, and the event cap holds however many writes arrive together.

`record_lobby/4` writes the same event to every open result of a lobby, for code that knows the lobby and not its players (a timer, a disconnect).

## Visibility

The words are KV's ([KV](/docs/key-value)): `public`, `owner_only` (the default), `lobby_members_only`, `owner_or_lobby_member`, `admin_only`, `server_only`. "Lobby member" is a player seated in the result's lobby now. An admin reads every result. The writer picks the visibility when the play starts, since the writer is the server.

## Reading, over the socket

A client that holds the user socket gets every event as it is written, and needs no other request while the play runs:

| Event | On | Carries |
|---|---|---|
| `result_started` | `user:<id>` | the result |
| `result_event` | `user:<id>` | `result_id` and the event |
| `result_ended` | `user:<id>` | the result |

The owner gets them unless the visibility is `server_only` or `admin_only`. A result its lobby's members may read is also broadcast on `lobby:<id>` to every member, so the owner seated there gets an event twice: the event's `id` is the same, and a client keeps one.

The reads are channel messages on `user:<id>`, answered in the reply:

| Message | Payload | Reply |
|---|---|---|
| `results:list` | `kind`, `status`, `page`, `page_size` | the caller's results, newest first, with each one's stats |
| `results:get` | `id` | the result and its stats |
| `results:events` | `id`, `after` (an event id), `limit` | the events after `after`, oldest first |

A client reconnecting asks `results:events` with the last event id it had, and has the play back.

## Reading, over HTTP

The same reads for a client that has no socket yet (boot), with the same visibility:

```
GET /api/v1/results              the caller's results (kind, status, page, page_size)
GET /api/v1/results/:id          one result and its stats
GET /api/v1/results/:id/events   its events (after, limit)
```

## At a glance

`Gamend.Results.stats/1` takes a result or a list of ids and answers each event key's `count` and `sum`, in one query whatever the number of results:

```elixir
%{"answer" => %{count: 10, sum: 7.0}, "hint" => %{count: 2, sum: 30.0}}
```

Asked is the count of `answer`, right is its sum, coins spent the sum of `hint`, how long the play took is `ended_at` less `started_at`. A page of results carries each one's stats. Pick event keys and values so these read straight off.

## Limits and retention

- `GAMEND_LIMITS_MAX_RESULT_EVENTS` (10,000): the events one result may hold. Past it a write answers `{:error, :too_many_events}`. Record what a player did, never a simulation's ticks.
- `metadata` on both rows is capped like every metadata map (`GAMEND_LIMITS_MAX_METADATA_SIZE`).
- `GAMEND_RETENTION_RESULTS_DAYS` (0, keep forever): results started more than N days ago are deleted, with their events.

## The admin page

[/admin/results](/admin/results) lists every result, filtered by kind, player, lobby and status, each with its event count and how long it ran. One result opens on its rows, its stats by key and its events in order, with each event's time into the play. A result can be deleted there.
