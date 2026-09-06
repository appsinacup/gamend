---
icon: hero-table-cells
---

# Key-Value Store

One `kv_entries` table stores JSON documents under a string key, each entry optionally scoped to a user, a lobby, or both. Server code writes; clients read over HTTP and subscribe over the realtime socket, which makes a KV row the standard way to hold server-authoritative state the game pushes to players the moment it changes.

## Scoping

| Scope | Entry belongs to | Typical use |
|---|---|---|
| global | nobody | game config, live-ops flags |
| `user_id` | one user | progress, save data |
| `lobby_id` | one lobby | shared match state |
| `user_id` + `lobby_id` | one user inside one lobby | ready flags, loadouts, character picks |

The key is unique *per scope*: a global `"progress"` and user A's `"progress"` are different entries. Namespacing is not built in. Encode it in the key (`"my_game:key1"`).

Per-member lobby state does not survive a leave: when a user stops being a lobby member, every entry scoped to that user *and* that lobby is deleted (`Gamend.KV.delete_user_lobby_entries/2`), so a leave-and-rejoin starts clean. Entries scoped to the lobby alone, or to the user alone, are left untouched.

## Who can read what

Clients never write KV. Writes come from server scripting or the admin API. The client surface is one endpoint, `GET /api/v1/kv/{key}` with optional `user_id` / `lobby_id` query parameters (see [/api/docs](/api/docs)), and whether it answers is decided by the `before_kv_get/2` hook. Return one access level per key:

- `:public`: any authenticated client (the default when no hook is registered)
- `:owner_only`: only the caller matching the requested `user_id`
- `:lobby_members_only`: only callers currently in the requested `lobby_id`
- `:owner_or_lobby_member`: either of the above
- `:admin_only`: admins only
- `:server_only`: no client reads at all

When several plugins implement the hook their decisions are intersected, and incompatible restrictions (or a hook that errors) fail closed to `:server_only`. Server-side `Gamend.KV.get/2` is unaffected; the hook governs only the client surface.

## Realtime subscriptions

The same hook decision gates the socket. A client pushes `"kv:subscribe"` with `key` and optional `user_id` / `lobby_id` on its user channel; the reply carries the current row, and from then on every change to that entry arrives as a `kv_updated` (with the new value) or `kv_deleted` event. `"kv:unsubscribe"` stops them.

## Godot client

`GamendClient` wraps this into a registry with automatic (re)subscription and a local row cache:

```gdscript
# Declare once; the client subscribes when the user channel joins,
# re-subscribes on reconnect, and keeps the latest row readable.
client.register_kv("progress", "", {"persist": true})
client.refresh_keys()
client.kv_row_changed.connect(func(key, row): print(key, " -> ", row))

# Cache-first read; a 404 caches {} as the authoritative "no row yet".
var row: Dictionary = await client.fetch_row("progress")
```

`register_kv` options: `user_scoped` (default `true`, subscribing under the current user's id), `persist` (mirror to disk across sessions), `subscribe` (`false` registers cache-only). Underneath sit `GamendApi.kv_get_kv(key, user_id, lobby_id)`, `kv_subscribe_ws` / `kv_unsubscribe_ws`, and the `kv_updated` / `kv_deleted` signals.

## Server scripting

```elixir
Gamend.KV.put("progress", %{level: 3}, %{}, user_id: user.id)
{:ok, %{value: value, metadata: meta}} = Gamend.KV.get("progress", user_id: user.id)
:ok = Gamend.KV.delete("match_state", lobby_id: lobby.id)

# Have a process react to changes; it then receives
# {:kv_updated, %{key: _, data: _, ...}} and {:kv_deleted, %{key: _, ...}}
Gamend.KV.subscribe("match_state", lobby_id: lobby.id)

Gamend.KV.list_entries(user_id: user.id, page: 1, page_size: 50)
Gamend.KV.count_entries(lobby_id: lobby.id)
```

## Typed schemas

KV values are JSON, but a plugin can map keys to protobuf messages by exporting `kv_schemas/0`, which lists exact keys or `*`-suffixed prefixes:

```elixir
def kv_schemas do
  %{"loadout" => MyGame.V1.Loadout, "match:*" => MyGame.V1.MatchState}
end
```

On protobuf sockets, `kv_updated` data for a matching key is pushed as compact binary (`data_pb`) instead of JSON bytes; storage and REST stay JSON, and data that does not fit the schema falls back to JSON so it is never dropped. Exact keys win over prefixes, the longest prefix wins, and the keyspace is global. When two plugins register the same pattern, the first plugin in name order wins and the loser is logged. Entry metadata always stays JSON.

## Caching and limits

Every read runs through the app cache with a 60-second TTL: writes re-warm the entry (evicting it on other instances first so no node serves the old value out its TTL), deletes evict it, and listings are versioned per scope. On a multi-node deploy the cache mode decides how that invalidation travels. See [Cache Setup](/docs/cache-setup).

- `GAMEND_LIMITS_MAX_KV_KEY` (512): maximum key length.
- `GAMEND_LIMITS_MAX_KV_VALUE_SIZE` (65536): maximum serialized value size, in bytes.
- `GAMEND_LIMITS_MAX_KV_ENTRIES_PER_USER` (1000): entries one user may hold; checked when an entry is created through the entries API (`create_entry/1`), not on `put/4` upserts.

## Operations

- **Admin → KV** (`/admin/kv`) browses every entry: filter by key substring, user, lobby, or global-only; create, edit, delete, and bulk-delete.
- The admin HTTP API mirrors it: `PUT` / `DELETE /api/v1/admin/kv` upsert and delete by key + scope, and `/api/v1/admin/kv/entries` lists and manages entries by row id.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.KV`](https://docs.gamend.org/Gamend.KV.html) - the functions a plugin calls, with their signatures and docs.
