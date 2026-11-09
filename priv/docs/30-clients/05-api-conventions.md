---
icon: hero-adjustments-horizontal-solid
---

# API Conventions

Every endpoint under `/api/v1` follows one set of mechanical conventions (the same envelope, the same id format, the same null policy), so a client written against one endpoint parses all of them. They are not aspirational: `mix gamend.api.lint` checks them in CI, which fails on any violation.

## Paths

Paths use `snake_case`, never hyphens: `/api/v1/me/push_tokens`. Collections are plural, a member is addressed by id, sub-resources hang off the member, and an action that is not CRUD is a verb segment on the member:

```text
GET  /api/v1/groups               # collection
GET  /api/v1/groups/:id           # one member
GET  /api/v1/groups/:id/members   # sub-resource
POST /api/v1/groups/:id/join      # action
```

## Identifiers

Every `id` (and every `<thing>_id` foreign key) is a UUIDv7 string. UUIDv7 embeds a unix-millisecond timestamp in its high bits, so ids sort in creation order (the server itself orders chat cursors and pages by id) while staying unguessable. Treat them as opaque; if you sort by them, oldest-first is what you get.

Beyond `id`, the identifier vocabulary is fixed:

| Field | Means |
|---|---|
| `slug` | URL-facing, human-typed, shared across a family of rows (every season of `weekly_kills`) |
| `key` | A unique machine handle that never appears in a URL segment (`daily_login`, a KV entry's key) |
| `sku` | An identifier owned by an external store (Steam / Play / App Store product) |
| `code` | A short symbolic value from a fixed vocabulary (currency `gold`) |

Tournaments accept either a UUID or a slug in the `:id` path segment and resolve the slug to the current occurrence, so `/api/v1/tournaments/weekend_gauntlet` stays a valid link from one week to the next. Leaderboards filter by slug instead: `GET /api/v1/leaderboards?slug=weekly_kills&active=true`.

Naming is equally fixed: a *thing* has a `title`; a *person* has a `username` (unique handle) and a `display_name` (chosen name). No field is called `name`.

## Time

An instant is named `*_at` and serialized as an ISO 8601 UTC string: `inserted_at`, `starts_at`, `resolved_at`. A duration is an integer whose name ends in its unit (`_ms`, `_sec`, `_min`, `_hours`, `_days`), so `round_window_sec: 30` never needs a docs lookup to interpret.

## Strings are never null

A string field never serializes as `null`: unset means `""`. An unset map means `{}`. This exists for statically typed game clients (GDScript crashes assigning JSON `null` to a `String`-typed variable), and it holds everywhere because the linter forbids both a serializer that passes a nullable string through raw (such schemas encode through `Gamend.SchemaJSON`, which reads each field's Ecto type and coalesces) and an OpenAPI schema that declares a string `nullable`, so generated clients agree with the wire.

Numbers, booleans and datetimes keep `null` where absence means something: `ends_at: null` is "permanent", `max_entries: null` is "unlimited". `0` and `false` would be lies.

```json
{"title": "Weekend Gauntlet", "icon_url": "", "metadata": {}, "ends_at": null}
```

```gdscript
var icon_url: String = data["icon_url"]   # "" when unset - safe to type
var ends_at = data["ends_at"]             # null is meaningful - keep it untyped
```

## Response shapes

Every JSON response is one of four shapes, and a test fails the server's build if an endpoint answers any other way:

| Shape | Answers | Body |
|---|---|---|
| Resource | a read, or a write with something to return | `{"data": {...}}` |
| Page | any list of records | `{"data": [...], "meta": {...}}` |
| Done | a write with nothing to return | `{"ok": true}` |
| Error | every 4xx and 5xx | `{"error": "code", "message": "..."}` |

Nothing else appears at the top level. A write returns what it wrote: creating a lobby answers `201` with the lobby under `data`, and changing your display name answers your whole profile. A list is always a page, with the same six `meta` keys:

```json
{"data": ["..."],
 "meta": {"page": 1, "page_size": 25, "count": 25,
          "total_count": 130, "total_pages": 6, "has_more": true}}
```

`count` is how many entries this page carries; `has_more` says a next page exists. Request the window with `?page=` and `?page_size=`, which the server clamps to its configured maximum. The one variation: an endpoint returning two parallel collections (pending friend requests) puts both lists under `data.incoming` / `data.outgoing`, with one standard meta each under `meta.incoming` / `meta.outgoing`.

The one list that is not a page is a fixed vocabulary, such as the enabled sign-in providers: an array of codes under `data`.

## Errors

An error is a snake_case machine code with the matching HTTP status:

```json
{"error": "not_in_lobby"}
```

Branch on the status and the `error` string: it is always `snake_case`, and codes like `blocked`, `not_friends` and `chat_daily_limit` are stable contract. A human-readable `message` may ride along; it is not.

The status follows the reason. `404` means the thing is not there, including your own current one: no party is `not_in_party`, no tournament match waiting is `no_current_match`, never a `null` under `data`. `409` means what you asked for already holds (`already_member`, `already_registered`, every `already_*`). `403` is a refusal (`full`, `registration_closed`, or `rejected` by the game's own hook, whose words are in `message`). `400` is a malformed request (`missing_param`). A rejected form answers `422` with `"error": "validation_failed"` and the per-field messages under `errors` (`409` when the clash is a uniqueness constraint, such as a taken group slug or username; a lobby's or a group's title is never unique); `errors` appears with no other code. An unknown `/api/v1` path, or any failure the server renders itself, returns the same shape: `404` with `{"error": "not_found", "message": "Not Found"}`.

## Binary uploads

Image bytes never travel through the API server. Uploads are two steps: request a presigned ticket, `PUT` the file straight to storage at the URL the ticket names, then confirm: for an avatar, `POST /api/v1/me/avatar/upload_url`, the `PUT`, then `POST /api/v1/me/avatar`. A ticket is bound to the exact storage key it was issued for, so a client cannot choose where its bytes land.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.UUIDv7`](https://docs.gamend.org/Gamend.UUIDv7.html) and [`Gamend.SchemaJSON`](https://docs.gamend.org/Gamend.SchemaJSON.html) - the id and encoding machinery behind these conventions.
