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

Timestamps are `inserted_at`/`updated_at` (from `Gamend.Schema`), UTC,
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
Encode through `Gamend.SchemaJSON`, which reads each field's Ecto type and
coalesces:

```elixir
defimpl Jason.Encoder, for: MySchema do
  def encode(struct, opts) do
    Gamend.SchemaJSON.encode(struct, [:id, :title, :icon_url], opts)
  end
end
```

**[R6]** An OpenAPI string property must not declare `nullable: true`,
unless it is a date or date-time. A schema that contradicts its serializer is
worse than no schema — clients generate code from it. The lint checks the
source line; `GamendWeb.ApiShapeTest` checks every property of the built
document, nested and referenced ones included.

## Response shapes

**[R15]** Every JSON response takes one of four shapes, and nothing else:

| Shape | Answers | Body | Helper |
|---|---|---|---|
| Resource | a read, or a write with something to return | `{"data": {...}}` | `reply_data/2,3` |
| Page | any list of records | `{"data": [...], "meta": PageMeta}` | `reply_page/5` |
| Done | a write with nothing to return | `{"ok": true}` | `reply_ok/1` |
| Error | every 4xx and 5xx | `{"error": "snake_case", "message": "...", "errors": {...}}` | `reply_error/3,4`, `unprocessable/2` |

The helpers live in `GamendWeb.Reply`, imported into every controller with
`unprocessable/2`; answering through them is how a controller stays inside
the table.

- **Top level is fixed.** `data` alone, `data` with `meta`, `ok` alone, or
  `error` with optional `message` and `errors`. Everything else — a member
  list, a spectator count, a cursor — goes inside `data`.
- **A write returns what it wrote.** Create answers 201 with the new resource,
  update the updated one (a profile change answers the whole current user).
  A write with nothing to show answers `{"ok": true}`, never `{}`.
- **A list is a page.** An array under `data` carries the six-key `meta` from
  `GamendWeb.Pagination`, even when the list is short today. The one
  exemption is a fixed vocabulary — an array of enum strings, such as the
  enabled sign-in providers. Two lists in one answer (friend requests) put an
  object of lists under `data` and one `PageMeta` per list under `meta`:

```json
{"data": [...], "meta": {"page": 1, "page_size": 25, "count": 25,
                         "total_count": 130, "total_pages": 6, "has_more": true}}
```

- **An error is a code.** `error` is a `snake_case` reason a client can switch
  on; `message` is optional prose for a person; nothing else rides along.
  Exceptions the endpoint renders (an unknown route, a crash) take the same
  shape: `{"error": "not_found", "message": "Not Found"}`.
- **The status follows the reason.** 404 for a thing that is not there,
  including the caller's own current thing (`not_in_party`,
  `no_current_match`: never `{"data": null}`); 409 when what was asked for
  already holds (`already_member`, `already_registered`, every `already_*`);
  403 for a refusal (`full`, `registration_closed`, a game hook's
  `rejected`, whose words go in `message`, and a quest not yet
  `not_completed`); 400 for a malformed request (`missing_param`,
  `invalid_index`); 503 when the server, not the request, lacks something
  (`stripe_not_configured`, every `*_not_configured`).

**[R18]** The status is the reason's, not the endpoint's. `GamendWeb.ErrorStatus`
gives each reason its status, once for every controller, and names the table
need not list follow the rules above: `*_not_found` 404, `already_*` and
`*_already_*` 409, `*_not_configured` 503. A controller matches the reasons it
answers its own way (another code, a header) and hands the rest to
`reply_reason(conn, reason)`:

```elixir
case Parties.leave_party(user) do
  {:ok, _party} -> reply_ok(conn)
  {:error, reason} -> reply_reason(conn, reason)
end
```

`reply_reason/2` answers an atom with its name and the table's status, a
failed changeset as `unprocessable_or_conflict/2`, and a hook's veto
(`{:hook_rejected, reason}`) as 403 `rejected`. A reason the table does not
know raises `GamendWeb.UnmappedReason`: a 500 whose log names the reason,
where a catch-all clause used to answer 400 or 403 for anything. Words that
mean different things in different places (`invalid`, `missing`, `disabled`)
have no status on purpose; a controller says which code each is.
`mix gamend.api.lint` flags, in an API controller, a status chosen for a
variable code (`reply_error(conn, :forbidden, reason)`), a reason thrown away
(`{:error, _} -> reply_error(...)`), a `with`'s `_ ->` that answers every
failure alike, and an explicit `reply_error(conn, status, "code")` whose
status the table disagrees with. A reason set open by design (a plugin's own
codes over `POST /api/v1/hooks/call`) says so with `# open-error: <why>` on
the line above.

**[R12]** A failed changeset adds the per-field detail under `errors`, keyed by
field, each value a list of already-interpolated, already-translated messages.
`errors` appears with `"error": "validation_failed"` and nowhere else, and
that answer is 422 — or 409 when what failed is a uniqueness constraint (a
group slug, an email or a username already taken):

```json
{"error": "validation_failed",
 "errors": {"max_players": ["must be greater than or equal to min_players"]}}
```

`unprocessable(conn, changeset)` is the only way to write it, and
`unprocessable_or_conflict(conn, changeset)` where the schema has a unique
index: it answers 409 when that index failed and 422 otherwise. A display
title (a lobby's, a group's) is never unique, so it never answers 409.
`GamendWeb.ChangesetErrors.errors/1` gives the map alone.
`mix gamend.api.lint` rejects a hand-rolled `traverse_errors` in a controller.

**[R16]** A person is named `<role>_name` (`host_name`, `sender_name`,
`leader_name`); a thing carries its `title` (`group_title`, never
`group_name`); no property is called `name`.

**[R17]** A miss is an answer, not a crash. An API controller or channel —
and a LiveView event or a job — looks a row up with the tuple/`nil` form and
answers the miss with its code, never with a `get_*!` whose
`Ecto.NoResultsError` happens to render 404 over HTTP and crashes everywhere
else. A crash in the server, a game hook's included, is 500 with the error
code and no detail: the log has the stack trace. `mix gamend.api.lint` flags
a raising lookup in those places; the rule behind it is "Errors" in
CONTRIBUTING.md.

**Enforcement.** `GamendWeb.ApiShapeTest` checks the OpenAPI document: every
success response is a named component in one of the first three shapes, every
error response is `ErrorResponse`, R16 holds for every property, and
no string but a date or date-time is nullable (R6). At run
time `GamendWeb.ResponseContract` checks every response the test suite
provokes against its documented schema, rejects undeclared keys, and holds
error bodies to the rules above. Together they mean a new endpoint cannot
answer in a fifth shape without failing CI. Both see only documented
operations, so **[R15]** in `mix gamend.api.lint` covers the source: an API
controller answers through `GamendWeb.Reply`, never `json/2`, and documents a
JSON response with a named `GamendWeb.Schemas` module, never an inline
`%Schema{}`. See
[named-api-schemas.md](named-api-schemas.md) for how the documented schemas
are named.

## Authentication in the document

An operation's `security` says what its route's pipeline enforces, because a
generated client sends the bearer token only where `security` asks for it:

| Route pipeline | `security` |
|---|---|
| `:api_auth` | `[%{"authorization" => []}]` |
| `:api_optional_auth` | `[%{}, %{"authorization" => []}]` — anonymous works, a signed-in caller sees more |
| neither | none |

`authorization` is the only scheme the document defines; a requirement naming
another (`"bearer"`) is skipped by generators, which then send nothing.
`GamendWeb.ApiSecurityTest` checks every `/api/v1` route against its
operation.

## Paths

**[R5]** Route paths use `snake_case` — `/me/push_tokens`, `/users/log_in`.
No hyphens, in API or page routes.

Collections are plural (`/groups`), a member is `/groups/:id`, a sub-resource
hangs off the member (`/groups/:id/members`). Actions that aren't CRUD are a
verb segment on the member: `/groups/:id/join`.

## Uploads

Two steps, never bytes through the app server:
`POST .../icon/upload_url` returns a presigned ticket, the client PUTs to
storage, `POST .../icon` confirms the key. `GamendWeb.Uploads` owns the
mechanism and confines a client-supplied key to its own entity's prefix.

## Running the checks

```
mix gamend.api.lint          # report violations, exit 1 if any
mix gamend.api.lint --list   # the rules
```

Rules live in `Gamend.ApiConventions`. Adding a rule means fixing every
existing violation in the same change — the linter has no baseline file and no
suppression comments, deliberately: a rule with exceptions is a rule nobody
trusts.

The task ships with `gamend_core`, so **host repos run the same check**:
polyglot and the starter call `gamend.api.lint` from their own precommits. The
scan roots are discovered (the host's `lib/` and `modules/*/lib`, plus core/web
whether as umbrella apps or deps), and R9 validates docs against whichever
router the host compiled (`GamendHost.Router` first).
