# API conventions

The vocabulary and shapes every schema, serializer and route follows. Rules
marked **[R#]** are enforced by `mix gamend.api.lint`, which CI runs; the rest
are conventions a reviewer applies.

This exists because the conventions were implicit for a year and drifted
exactly where nobody looked: 16 fields serialized `null` against a documented
never-null policy, OpenAPI schemas contradicted their own serializers, six
schemas bypassed every serializer through `@derive`, and one duration setting
shipped with no unit in its name. A convention nothing enforces is a
suggestion.

## Identifiers

| Name | Means | Example |
|---|---|---|
| `id` | The row's UUIDv7 primary key. Every table, no exceptions. | `0198c0de-…` |
| `slug` | URL-facing, human-typed, **shared across a family** of rows | `weekly_kills` (every season), `weekend_gauntlet` (every occurrence) |
| `key` | A stable machine handle that never appears in a URL segment | `daily_login`, a KV entry's key |
| `sku` | An identifier owned by an external commerce system | Steam/Play/App Store product |
| `code` | A short symbolic value from a fixed vocabulary | currency `gold` |

`slug` and `key` are not interchangeable: a slug is deliberately non-unique
(leaderboard seasons and tournament occurrences reuse one), a key is unique.

Foreign keys are `<thing>_id`, always the referenced row's UUID.

**Resolving `:id`.** Tournaments and leaderboards accept *either* a UUID or a
slug in the `:id` path segment, resolving the slug to the current occurrence.
That is deliberate — `/tournaments/weekend_gauntlet` is the useful link — and
must stay documented in each endpoint's OpenAPI description.

## Names

| Name | Means |
|---|---|
| `title` | An entity's display name (group, quest, tournament, leaderboard, lobby, product) |
| `display_name` | A **person's** chosen name, alongside their `username` handle |
| `username` | A person's unique handle |
| `label` | Free text standing in for a person who isn't one — a scoreboard row with no user |

A thing has a `title`. A person has a `username` and a `display_name`. Do not
add `name` to a schema; it says nothing the three above don't say better.

## Time

**[R3]** An instant is `:utc_datetime` and named `*_at` — `starts_at`,
`resolved_at`, `deadline_at`. Nothing else may end in `_at`.

**[R4]** A duration is an integer and **names its unit**: `_ms`, `_sec`,
`_min`, `_hours`, `_days`. `round_window_sec`, `queue_interval_ms`,
`chat_messages_days`. A bare `timeout` or `window` is rejected — the reader
should never have to open the docs to learn whether `1000` is a second or a
second and a half.

Timestamps are `inserted_at`/`updated_at` (from `GameServer.Schema`), UTC,
serialized ISO 8601.

## Lifecycle and enums

A lifecycle field is `status`, holds a `:string`, and is constrained with
`validate_inclusion` against a module attribute listing the values. It is not
an `Ecto.Enum` — those serialize as atoms and force every serializer to
`to_string/1` them, which is exactly the kind of per-entity special case this
document exists to remove.

> **Not yet true.** Four schemas still call this field `state` (lobbies,
> tournaments, tournament entries, ready-check participants); Phase 2 of the
> standardization plan renames them. Until then, new schemas use `status` +
> string. Leaderboards' `sort_order`/`operator` stay `Ecto.Enum` deliberately:
> they are classifications, not lifecycle, and converting them would trade two
> `to_string/1` calls in one serializer for seven pattern-match rewrites in
> the scoring engine.

`type`, `kind`, `category` and `provider` are classifications, not lifecycle —
they say what a row *is*, not where it is in a process.

## Null policy

A string is **never `null`**. An unset string serializes as `""`, an unset map
as `{}`. Game clients — Godot in particular — crash where they expect a string
and receive `null`.

Numbers, booleans and datetimes keep `null` when absence is meaningful:
`ends_at: null` means permanent, `max_entries: null` means unlimited. `0` and
`false` would be lies.

**[R1]** A nullable string/map schema field must be coalesced where it is
serialized.

**[R2]** A schema with nullable string/map fields must not use
`@derive Jason.Encoder` — that emits raw values, bypassing every serializer.
Encode through `GameServer.SchemaJSON`, which reads each field's Ecto type and
coalesces:

```elixir
defimpl Jason.Encoder, for: MySchema do
  def encode(struct, opts) do
    GameServer.SchemaJSON.encode(struct, [:id, :title, :icon_url], opts)
  end
end
```

**[R6]** An OpenAPI string property must not declare `nullable: true`. A
schema that contradicts its serializer is worse than no schema — clients
generate code from it.

## Response shapes

Reads return `data`, plus `meta` when paginated:

```json
{"data": [...], "meta": {"page": 1, "page_size": 25, "count": 25,
                         "total_count": 130, "total_pages": 6, "has_more": true}}
```

All six meta keys, always, via `GameServerWeb.Pagination.meta/4`. Mutations
return `data` with the affected resource, or `{"ok": true}` when there is
nothing to return. Errors return `{"error": "snake_case_reason"}` with a
matching HTTP status.

An endpoint returning two parallel collections (friend requests) nests one
standard meta per collection under `meta.incoming` / `meta.outgoing` rather
than inventing a parallel-map shape.

## Paths

**[R5]** Route paths use `snake_case` — `/me/push_tokens`, `/users/log_in`.
No hyphens, in API or page routes.

Collections are plural (`/groups`), a member is `/groups/:id`, a sub-resource
hangs off the member (`/groups/:id/members`). Actions that aren't CRUD are a
verb segment on the member: `/groups/:id/join`.

## Uploads

Two steps, never bytes through the app server:
`POST .../icon/upload_url` returns a presigned ticket, the client PUTs to
storage, `POST .../icon` confirms the key. `GameServerWeb.Uploads` owns the
mechanism and confines a client-supplied key to its own entity's prefix.

## Running the checks

```
mix gamend.api.lint          # report violations, exit 1 if any
mix gamend.api.lint --list   # the rules
```

Rules live in `GameServer.ApiConventions`. Adding a rule means fixing every
existing violation in the same change — the linter has no baseline file and no
suppression comments, deliberately: a rule with exceptions is a rule nobody
trusts.

The task ships with `game_server_core`, so **host repos run the same check**:
polyglot and the starter call `gamend.api.lint` from their own precommits. The
scan roots are discovered (the host's `lib/` and `modules/*/lib`, plus core/web
whether as umbrella apps or deps), and R9 validates docs against whichever
router the host compiled (`GameServerHost.Router` first).
