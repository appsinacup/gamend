---
icon: hero-archive-box
---

# Object Storage & Uploads

`Gamend.Storage` is a thin facade over one of two backends, local disk (the default) or any S3-compatible service. Every user-supplied image reaches it the same way: the server issues an upload ticket, the client PUTs the bytes straight to storage, then confirms the key. The bytes never transit the app server, and the ticket shape is identical for both backends, so client code does not change between environments.

## Backends

```bash
# Local disk (the default)
GAMEND_STORAGE_ADAPTER=local
GAMEND_STORAGE_DIR="/mnt/data/storage"   # default priv/storage — point at a
                                         # mounted volume; the default lives with
                                         # the app and does not survive a redeploy

# Any S3-compatible service (AWS S3, Cloudflare R2, Backblaze B2, MinIO, Spaces)
GAMEND_STORAGE_ADAPTER=s3
GAMEND_STORAGE_BUCKET=my-bucket
GAMEND_STORAGE_ACCESS_KEY_ID=...
GAMEND_STORAGE_SECRET_ACCESS_KEY=...
GAMEND_STORAGE_REGION=auto               # "auto" for services without one (R2, MinIO)
GAMEND_STORAGE_ENDPOINT="https://<account>.r2.cloudflarestorage.com"

# Either backend: CDN or base URL objects are served from
GAMEND_STORAGE_PUBLIC_URL="https://cdn.example.com"
```

With the `s3` adapter selected, bucket and both credentials are required in production; a missing one fails the boot rather than warns.

## The two-step upload

```text
POST .../upload_url  ──►  %{url, method, headers, key, expires_in}
PUT  <ticket.url>         (client -> storage, direct)
POST .../icon             %{"key" => key}     (confirm)
```

There is deliberately no generic `POST /uploads`: authorization is a property of the *target* (only you may set your avatar, only a group admin that group's icon), so each entity keeps its own endpoint pair and only the mechanism is shared. The pairs are `/api/v1/me/avatar/upload_url` + `/me/avatar` for the caller's avatar, and `.../icon/upload_url` + `.../icon` under groups, leaderboards, tournaments and quests (see [/api/docs](/api/docs); in the Godot addon these are `user_create_current_user_avatar_upload_url` and `user_set_current_user_avatar` on `GamendApi`).

The object key is server-chosen (`<namespace>/<owner_id>/<random><ext>` via `Storage.build_key/3`, e.g. `avatars/<user_id>/…` or `icons/groups/<group_id>/…`), so a client can neither pick a key nor overwrite another object, and every change mints a fresh key.

## What is checked, and where

The backends give different guarantees at upload time, so the checks are split:

- **At ticket time** (both backends): the declared content type must be in the allow-list: `image/png`, `image/jpeg`, `image/webp`, `image/gif` by default.
- **At upload time** (local only): the size cap, the per-owner quota, and magic-byte sniffing all run, because the bytes pass through `PUT /storage/upload`. On the local backend the key also travels inside a signed token, never the query string.
- **At confirm time** (both backends): size and magic bytes are re-checked against the *stored* object, and a failing object is deleted. On S3 a presigned PUT goes straight to the bucket, so confirm is the only point at which the server sees the object at all, so nothing may persist an object URL without going through it.

Two limits bound the whole surface: `GAMEND_LIMITS_MAX_UPLOAD_BYTES` (5 MiB per object) and `GAMEND_LIMITS_MAX_UPLOAD_BYTES_PER_OWNER` (50 MiB per owner prefix, the cap on orphans left by tickets a client requests but never confirms).

## Serving

On the local backend, objects are served by `GET /storage/*key` from the app itself; on S3 the object URL points at the bucket (or at `GAMEND_STORAGE_PUBLIC_URL` when set) and that route is unused. Cache policy is keyed by prefix: `avatars/` and `icons/` are immutable for a year, because every change mints a new key and makes their URL content-unique. Everything else revalidates via ETag. The serve route labels only real image bytes as images; any other stored type comes back as an opaque download, never rendered from the app's origin.

## Server scripting

```elixir
key = Gamend.Storage.build_key("avatars", user.id, "me.png")
{:ok, ticket} = Gamend.Storage.presigned_upload(key, content_type: "image/png")

Gamend.Storage.url(key)                       # public or signed, backend-dependent
{:ok, data} = Gamend.Storage.get(key)
{:ok, %{size: _, content_type: _}} = Gamend.Storage.stat(key)
:ok = Gamend.Storage.delete(key)

Gamend.Storage.usage(prefix: "avatars/")      # %{count: _, bytes: _}
Gamend.Storage.list_objects(prefix: "icons/", offset: 0, limit: 50)
{:ok, removed} = Gamend.Storage.delete_prefix("avatars/#{user.id}/")
```

`Gamend.Storage.sniff_content_type/1` and `validate_upload/3` are the same checks the upload path uses, for code that stores objects of its own.

## Operations

- **Admin → Storage** (`/admin/storage`): usage summary (object count and bytes), a paginated object list filterable by key prefix with preview and per-object delete, and a direct upload. Backend-agnostic: the page works the same over local disk and S3.
- The admin HTTP API mirrors it: `GET` / `DELETE /api/v1/admin/storage` and `PUT` / `GET /api/v1/admin/storage/object`.
- Stored avatars whose owner no longer exists are swept automatically; see [Data Retention](/docs/data-retention).

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Storage`](https://docs.gamend.org/Gamend.Storage.html) - the functions a plugin calls, with their signatures and docs.
