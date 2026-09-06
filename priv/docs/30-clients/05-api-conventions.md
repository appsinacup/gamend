---
icon: hero-adjustments-horizontal
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

Reads return the payload under `data`. Paginated lists add `meta`, always with the same six keys, and no endpoint omits any of them:

```json
{"data": ["..."],
 "meta": {"page": 1, "page_size": 25, "count": 25,
          "total_count": 130, "total_pages": 6, "has_more": true}}
```

`count` is how many entries this page carries; `has_more` says a next page exists. Request the window with `?page=` and `?page_size=`, which the server clamps to its configured maximum. The one variation: an endpoint returning two parallel collections (pending friend requests) puts both lists under `data.incoming` / `data.outgoing`, with one standard meta each under `meta.incoming` / `meta.outgoing`.

Mutations return `data` with the affected resource, or `{"ok": true}` when there is nothing worth returning, sometimes with a detail alongside, e.g. `{"ok": true, "removed": 3}`.

## Errors

An error is a snake_case machine code with the matching HTTP status:

```json
{"error": "not_in_lobby"}
```

Branch on the status and the `error` string. Codes like `blocked`, `not_friends` and `chat_daily_limit` are stable contract; a few responses add a human-readable `message` alongside, which is not. An unknown `/api/v1` path returns the same shape, `404` with `{"error": "not_found"}`.

## Binary uploads

Image bytes never travel through the API server. Uploads are two steps: request a presigned ticket, `PUT` the file straight to storage at the URL the ticket names, then confirm: for an avatar, `POST /api/v1/me/avatar/upload_url`, the `PUT`, then `POST /api/v1/me/avatar`. A ticket is bound to the exact storage key it was issued for, so a client cannot choose where its bytes land.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.UUIDv7`](https://docs.gamend.org/Gamend.UUIDv7.html) and [`Gamend.SchemaJSON`](https://docs.gamend.org/Gamend.SchemaJSON.html) - the id and encoding machinery behind these conventions.
