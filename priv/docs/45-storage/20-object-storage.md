---
icon: hero-archive-box-solid
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

On Gamend Cloud, set these on the server's **Settings** tab under Storage, then restart it. `GAMEND_STORAGE_DIR` stays the server's own disk. Switching does not move files already stored: download **Stored files** from the **Backups** tab, unpack it and upload what is inside `storage/` to the bucket.

## The two-step upload

```text
POST .../upload_url  ──►  %{url, method, headers, key, expires_in}
PUT  <ticket.url>         (client -> storage, direct)
POST .../icon             %{"key" => key}     (confirm)
```

There is deliberately no generic `POST /uploads`: authorization is a property of the *target* (only you may set your avatar, only a group admin that group's icon), so each entity keeps its own endpoint pair and only the mechanism is shared. The pairs are `/api/v1/me/avatar/upload_url` + `/me/avatar` for the caller's avatar, and `.../icon/upload_url` + `.../icon` under groups, leaderboards, tournaments and quests (see [/api/docs](/api/docs); in the Godot addon these are `user_create_current_user_avatar_upload_url` and `user_set_current_user_avatar` on `GamendApi`).

The object key is server-chosen (`<namespace>/<owner_id>/<random><ext>` via `Storage.build_key/3`, e.g. `avatars/<user_id>/…` or `icons/groups/<group_id>/…`), so a client can neither pick a key nor overwrite another object, and every change mints a fresh key. Confirming an avatar drops the pictures it replaces, as the settings page's Save does.

On the local backend the ticket's `url` is `/api/v1/storage/upload?key=…&token=…`, a path with no host: the client sends it to the server it talks to. The `token` signs the key and the content type, and it is all the route takes, as an S3 presigned URL is: PUT the bytes with the ticket's `headers` and no session. An S3 ticket's `url` is the bucket's. Either is a capability for one key until `expires_in` (`GAMEND_STORAGE_UPLOAD_TTL_SECONDS`): a ban or a sign-out after it was issued does not void it, and confirm, which takes the session, is where the object reaches the account. The Balaur SDK's `core::upload(ticket, bytes)` does either.

### Why an upload is refused

Each refusal has its own `error`, so a client says what the site's settings page says for it:

| Step | `error` (status) | Means | The site says |
|---|---|---|---|
| ticket | `unsupported_content_type` (400) | not PNG, JPEG, WebP or GIF | File is too large or not a supported image. |
| ticket, confirm | `anonymous_avatar_disabled` (403) | a guest may not set an avatar | Link an email or a sign-in provider to set a custom avatar. |
| ticket, confirm | `not_found` (404) | `GAMEND_FEATURES_USER_IMAGE_UPLOADS` is off | Avatar uploads are not available. |
| upload | `invalid_token` (403) | not a ticket this server signed | Could not update avatar. |
| upload | `ticket_expired` (403) | older than its `expires_in` | Could not update avatar. |
| upload | `key_mismatch` (403) | `?key=` is not the ticket's | Could not update avatar. |
| upload | `content_type_mismatch` (415) | sent as another type than the ticket's | File is too large or not a supported image. |
| upload | `too_large` (413) | over `GAMEND_LIMITS_MAX_UPLOAD_BYTES` | File is too large or not a supported image. |
| upload | `content_mismatch` (415) | the bytes are not the ticket's type | That file is not a valid image. |
| upload | `quota_exceeded` (507) | the owner's prefix is full | Could not update avatar. |
| upload | `storage_unavailable` (503) | the backend failed | Could not update avatar. |
| confirm | `missing_key` (400) | no `key` | Could not update avatar. |
| confirm | `key_not_owned` (403) | the key is not under the target's prefix | Could not update avatar. |
| confirm | `object_not_found` (400) | nothing was uploaded there | Could not update avatar. |
| confirm | `too_large` (413) | the stored object is over the cap (deleted) | File is too large or not a supported image. |
| confirm | `not_an_image` (415) | the stored bytes are no image (deleted) | That file is not a valid image. |

The site's words are core's msgids (`gettext`), so a client in another language finds them in the site's catalogue.

## What is checked, and where

The backends give different guarantees at upload time, so the checks are split:

- **At ticket time** (both backends): the declared content type must be in the allow-list: `image/png`, `image/jpeg`, `image/webp`, `image/gif` by default.
- **At upload time** (local only): the ticket's expiry, its key and content type, the size cap, the per-owner quota, and magic-byte sniffing all run, because the bytes pass through `PUT /api/v1/storage/upload`. On the local backend the key and the content type travel inside the signed token, never the query string.
- **At confirm time** (both backends): size and magic bytes are re-checked against the *stored* object, and a failing object is deleted. On S3 a presigned PUT goes straight to the bucket, so confirm is the only point at which the server sees the object at all, so nothing may persist an object URL without going through it.

Two limits bound the whole surface: `GAMEND_LIMITS_MAX_UPLOAD_BYTES` (5 MiB per object) and `GAMEND_LIMITS_MAX_UPLOAD_BYTES_PER_OWNER` (50 MiB per owner prefix, the cap on orphans left by tickets a client requests but never confirms).

## Serving

On the local backend, objects are served by `GET /storage/*key` from the app itself. On S3 with `GAMEND_STORAGE_PUBLIC_URL` set, the object URL points there. On S3 without it the bucket is private: the stored URL is `/storage/<key>`, which redirects to a link signed for `GAMEND_STORAGE_SIGNED_URL_SECONDS` (default `3600`), so a URL saved as a player's avatar keeps working after any one signed link expires. Upload tickets last `GAMEND_STORAGE_UPLOAD_TTL_SECONDS` (default `600`) on both backends, and `expires_in` on the ticket says so. The route serves only the key prefixes in `GAMEND_STORAGE_PUBLIC_PREFIXES` (default `avatars/,icons/`); every other key is reached through the admin API. Add a prefix only for keys as random as an avatar's, never for hand-named ones. Cache policy is keyed by prefix: `avatars/` and `icons/` are immutable for a year, because every change mints a new key and makes their URL content-unique. Everything else revalidates via ETag. The serve route labels only real image bytes as images; any other stored type comes back as an opaque download, never rendered from the app's origin.

## Server scripting

```elixir
key = Gamend.Storage.build_key("avatars", user.id, "me.png")
{:ok, ticket} = Gamend.Storage.presigned_upload(key, content_type: "image/png")

Gamend.Storage.url(key)                       # stable URL, safe to store
Gamend.Storage.url(key, signed: true)         # short-lived signed link (private S3); never store it
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
- The admin HTTP API mirrors it: `GET` / `DELETE /api/v1/admin/storage` (a page of objects), `GET /api/v1/admin/storage/usage` (count and bytes under a `prefix`), and `PUT` / `GET /api/v1/admin/storage/object`.
- Stored avatars whose owner no longer exists are swept automatically; see [Data Retention](/docs/data-retention).
- An OAuth sign-in stores the provider's avatar URL, and `Gamend.Accounts.AvatarMirror` (queue `storage`) copies the image to `avatars/<user_id>/…` and points `profile_url` at the copy, unless `GAMEND_FEATURES_USER_IMAGE_UPLOADS` is off, when it copies nothing. Until it succeeds, and when it gives up, the provider URL stays in the row and is never shown: pages, realtime payloads and API answers read `User.public_avatar_url/1`, which returns only an avatar under the user's own `avatars/<id>/` key and nil otherwise. A hotlinked provider image would send each viewer's IP to the provider, and a Discord one names the player's Discord account.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Storage`](https://docs.gamend.org/Gamend.Storage.html) - the functions a plugin calls, with their signatures and docs.
