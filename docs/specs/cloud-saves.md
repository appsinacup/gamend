# Cloud saves — versioned save-slots

Design spec for the Phase 2 **Cloud saves** item in
[ROADMAP.md](../../ROADMAP.md). Depends on **Object storage** (Phase 0, shipped)
— this is a thin, versioned context layered on `GameServer.Storage`.

Goal: let a player's progress follow them across devices — named **save slots**,
each holding a **versioned** blob, with **conflict detection** so two devices
can't silently clobber each other. Blob bytes live in object storage; only small
metadata lives in the database.

## Why (Storage moves bytes; it doesn't version them)

`GameServer.Storage` already does direct client uploads (presigned PUT straight
to disk/S3/R2) and `KV` already stores small JSON maps — but neither gives a
save the three things a save needs: **slots** (multiple named saves per game),
**versions** (rollback + "which is newer?"), and **conflict detection** (device
A and device B both edited version 5). Cloud saves adds exactly that thin layer
and reuses Storage's presigned flow unchanged, so the client upload code is the
same one avatars use.

## Data model (both adapters)

- **`save_slots`** — one row per `(user_id, slot)`: `slot` (string key or small
  int, author-defined, e.g. `"main"` / `"0"`), `name`, `current_version`
  (integer, monotonic), `storage_key` (current blob), `size`, `checksum`
  (client-supplied SHA-256, for integrity + dedupe), `device_id` (who wrote it),
  `updated_at`. `unique_index([:user_id, :slot])`.
- **`save_versions`** — history for rollback: `slot_id`
  (`references(:save_slots, on_delete: :delete_all)`), `version`, `storage_key`,
  `size`, `checksum`, `inserted_at`. `unique_index([:slot_id, :version])`;
  `index([:slot_id, :version])` serves both the history list and the prune sweep.

Blob keys are deterministic per version — `saves/<user_id>/<slot>/<version>` —
via `Storage.put/2` with an explicit key (not `build_key/3`'s random scheme),
so a version maps to exactly one object and pruning is unambiguous.

## Conflict detection — optimistic, lock-free

A save write carries the `base_version` the client started from. The version
bump is expressed as a **conditional update** rather than a lock:

```elixir
from(s in SaveSlot, where: s.user_id == ^uid and s.slot == ^slot and s.current_version == ^base_version)
|> Repo.update_all(set: [current_version: base_version + 1, storage_key: ^key, ...])
```

`{0, _}` affected rows ⇒ someone else advanced the slot ⇒ `{:error, {:conflict, current}}`
(the client re-reads and merges). `{1, _}` ⇒ committed. This is cross-adapter,
needs no advisory lock, and is the standard optimistic-concurrency pattern —
appropriate because a save write is idempotent per version and conflicts are
rare but must never be silently lost. (A brand-new slot writes with
`base_version = 0` guarded by the `unique_index`.)

## Upload / download flow (reuses Storage's presigned path)

**Write:**
1. `POST /me/saves/:slot/upload-url {size, checksum}` → server validates size vs
   `max_save_bytes`, returns a `Storage.presigned_upload/2` ticket for
   `saves/<user_id>/<slot>/<next_version>`.
2. Client PUTs the blob straight to the backend (identical to avatar upload).
3. `POST /me/saves/:slot {key, base_version, size, checksum}` → server verifies
   the object exists (`Storage.exists?/1`), runs the conditional version bump,
   records `save_versions`, and prunes versions beyond `max_save_versions_kept`
   (deleting their storage objects too).

**Read:** `GET /me/saves/:slot` → metadata + a `Storage.url/2` read URL for the
current blob. `GET /me/saves` → list all slots (paginated `meta`).
`GET /me/saves/:slot/versions` → history for rollback.
`POST /me/saves/:slot/restore/:version` → promotes an old version to current
(new version pointing at the old blob).

A small-save convenience (inline base64 through the app, capped at a low
`max_inline_save_bytes`) is offered for tiny saves so trivial games skip the
three-step dance; anything larger must use the presigned flow.

## `GameServer.CloudSaves` — the context

```elixir
CloudSaves.put_slot(user_id, slot, %{key: ..., base_version: 5, size: ..., checksum: ...})
CloudSaves.get_slot(user_id, slot)                 # metadata + read url
CloudSaves.list_slots(user_id, opts)               # paginated + count_slots/1
CloudSaves.list_versions(user_id, slot, opts)      # + count_versions/…
CloudSaves.restore(user_id, slot, version)
CloudSaves.delete_slot(user_id, slot)              # removes row + all version blobs
```

## Hooks (all six places, per CONTRIBUTING §Hooks)

- **`before_save_write(user_id, slot, meta)`** — pipeline veto/validate (size
  policy, anti-cheat schema checks the host wants to run on metadata). Add to
  `lifecycle_pipeline_hook?/2` + `normalize_pipeline_args/3`.
- **`after_save_written(save_slot)`** — observe (e.g. mirror to analytics).

Both dispatched after commit, never inside the update; RPC-blocked;
SDK-mirrored in all six places.

## Limits (`GameServer.Limits`, auto `LIMIT_*`, `@limit_categories`)

`max_save_slots_per_user`, `max_save_bytes`, `max_inline_save_bytes`,
`max_save_versions_kept`.

## Admin

- `admin_live/cloud_saves.ex` — per-user slots (sizes, versions, last device),
  view/delete a slot, total storage used by saves (via `Storage.usage(prefix: "saves/")`).
- `/admin` stat card (total saved games, bytes) + route + nav +
  `admin_pages_render_test`.
- Admin API parity (list, delete a user's slot).

## "Update everywhere" — file list

- **README** Features: Cloud saves. **CHANGELOG** `[added]` Cloud saves
  (versioned slots).
- **.env.example** — the `LIMIT_*` caps (storage vars already documented).
- **host_public_docs/** — new Cloud saves page (slots, versioning, conflict flow,
  reuse of the presigned upload); Data Schema gains `save_slots` / `save_versions`.
- **api_spec.ex** — feature list + save endpoints (+ realtime `save_updated`
  event if we push cross-device — see deferred).
- **SDK** — `CloudSaves` stub + struct stubs; `@sdk_modules`, `gen.sdk`,
  placeholder rules; hooks mirrored.
- **runtime_introspection.ex** — save counts + bytes.
- **i18n** — 30 locales; **mix demo.seed** — a couple of seeded slots with
  version history (Local storage) so the admin page shows data.

## Deferred / rejected

- **Server-side merge / CRDT save resolution: rejected for core.** The server
  can't know a game's save semantics; it detects the conflict and hands both
  versions to the client, which merges. A game that wants auto-merge does it in
  `before_save_write`.
- **Cross-device realtime "save updated" push: defer.** A `save_updated` PubSub
  event on the user channel is a small follow-up; v1 is pull-on-launch.
- **Encryption-at-rest beyond the backend's own: defer.** S3/R2 SSE covers most;
  client-side encryption is a game concern (store ciphertext, server never
  inspects it).

## Definition of done (CONTRIBUTING)

- [ ] Migrations for `save_slots` / `save_versions` apply on SQLite **and**
      `GAMEND_DB_ADAPTER=postgres`; indexes as above.
- [ ] Conditional-update conflict detection (no silent clobber); version prune
      deletes old blobs; presigned + small-inline write paths; restore.
- [ ] Paginated `list_*`/`count_*`; `Limits` caps enforced.
- [ ] Hooks `before_save_write` / `after_save_written` in all six places,
      RPC-blocked, SDK-mirrored.
- [ ] Admin page + `/admin` card + route + nav + `admin_pages_render_test`;
      admin API parity.
- [ ] Docs, `.env.example`, CHANGELOG, README, `api_spec.ex`; i18n 30 locales.
- [ ] Tests: context + controller + admin + LiveView, both adapters (Local +
      an S3 mock); boot and actually round-trip a save, trigger a version
      conflict, prune old versions, and restore.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
