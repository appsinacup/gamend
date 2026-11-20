---
icon: hero-table-cells-solid
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

Clients never write KV. Writes come from server scripting or the admin API. The client surface is one endpoint, `GET /api/v1/kv/{key}` with optional `user_id` / `lobby_id` query parameters (see [/api/docs](/api/docs)), and whether it answers is decided by the `before_kv_get/2` hook. It answers the entry as the realtime `kv_updated` event carries it: `{"data": {"key", "user_id", "lobby_id", "data", "metadata"}}`, the stored value under the inner `data` and an unset owner as `""`. A missing entry is `not_found` (404), a refused read `forbidden` (403). Return one access level per key:

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

## C++ client

`client.kv()` keeps the same registry and row cache:

```cpp
// Subscribes now or when the user channel joins, and again on reconnect.
client.kv().subscribe({"progress", user_id});
client.kv().on_change([](const gamend::KvKey& key, const gamend::KvRow& row) {
  if (key.key == "progress" && row.exists) show(row.data);
});

// Cache-first read; a 404 caches "no row yet" (row.exists == false).
client.kv().fetch({"progress", user_id}, false, [](const gamend::KvResult& r) {
  if (r.ok) show(r.row.data);
});
```

`kv().row(key)` is the latest cached value from any source. See the
[C++ SDK](/docs/cpp-sdk) guide.

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

## Computed rows

A page often draws more than what is stored: a level from the points banked, a track with what is owned. A computed row gives a client the same value, live, without a second copy to keep in step. The host names it and what it is worked out from:

```elixir
config :gamend_core, :computed_rows, %{
  "level" => %{value: {MyGame.Level, :row}, from: ["points"]}
}

# Called with the scope asked for; a map is the row, anything else no row.
def row(%{user_id: user_id}), do: %{"level" => level_of(user_id)}
```

| | A computed row |
|---|---|
| Read | as any row: `Gamend.KV.get/2`, `GET /api/v1/kv/level`, `kv:subscribe`, behind the same `before_kv_get/2` decision |
| Stored | nowhere: the function runs on each read |
| Moves | when a key in `from` is written or deleted in the same scope, or the host calls `Gamend.KV.refresh("level", user_id: id)` for what lives outside the store |
| Pushed | a subscribed client gets `kv_updated` with the new value (`kv_deleted` where it is gone), read once for a burst of changes; with nobody subscribed nothing is computed |

A server process subscribed to it (`Gamend.KV.subscribe/2`) receives `{:kv_stale, %{key: _, user_id: _, lobby_id: _}}` and reads it itself.

A key ending in `*` is a family, a row for every part: one a language, worked out from that language's stored row.

```elixir
config :gamend_core, :computed_rows, %{
  "word_pools:*" => %{value: {MyGame.WordPools, :row}, from: ["words:*"]}
}

# `word_pools:fr` is called with `part: "fr"`; a write of `words:fr` moves it alone.
def row(%{user_id: user_id, part: language}), do: pools_of(user_id, language)
```

A key named whole wins over a family and the longest prefix over a shorter one, as `kv_schemas` patterns do.

A row only its owner may read says so with `access`, in the words `before_kv_get/2` answers in. That is the least a reader must be: a plugin can close the row further, never open it, and on a host with no plugin it holds all the same.

```elixir
"word_pools:*" => %{value: {MyGame.WordPools, :row}, from: ["words:*"], access: :owner_only}
```

### The account's preferences

Core computes one row itself: `preferences`, what a page or a client may set on the account (`Gamend.Accounts.Preferences.client_keys/0`: the theme, and what the host adds to `config :gamend_core, :client_preferences`), its owner's only. A client sets one with `PUT /api/v1/me/preferences` (`{"key": "theme", "value": "dark"}`; `system` removes the theme), the site's page with `PUT /preferences`, and every change moves the row, so a second device is pushed the theme or the sound the first one changed.

```json
{"theme": "dark", "game_sounds": "off"}
```

A host's `:client_preferences` value is the list of what a key may be, or a `{module, function}` that answers it, such as the languages the site serves (`%{"locale" => {MyGame.Locales, :all}}`). A host's row under the same key replaces core's.

## Typed schemas

KV values are JSON, but a plugin can map keys to protobuf messages by exporting `kv_schemas/0`, which lists exact keys or `*`-suffixed prefixes:

```elixir
def kv_schemas do
  %{"loadout" => MyGame.V1.Loadout, "match:*" => MyGame.V1.MatchState}
end
```

On protobuf sockets, `kv_updated` data for a matching key is pushed as compact binary (`data_pb`) instead of JSON bytes; storage and REST stay JSON, and data that does not fit the schema falls back to JSON so it is never dropped. Exact keys win over prefixes, the longest prefix wins, and the keyspace is global. When two plugins register the same pattern, the first plugin in name order wins and the loser is logged. Entry metadata always stays JSON.

## Caching and limits

Every read runs through the app cache with a 60-second TTL: writes and deletes evict the entry on every instance, so no node serves the old value out its TTL, and listings are versioned per scope. On a multi-node deploy the cache mode decides how that invalidation travels. See [Cache Setup](/docs/cache-setup).

- `GAMEND_LIMITS_MAX_KV_KEY` (512): maximum key length.
- `GAMEND_LIMITS_MAX_KV_VALUE_SIZE` (65536): maximum serialized value size, in bytes.
- `GAMEND_LIMITS_MAX_KV_ENTRIES_PER_USER` (1000): entries one user may hold; checked when an entry is created through the entries API (`create_entry/1`, `POST /api/v1/admin/kv/entries`, which answers 403 `too_many_entries` past it), not on `put/4` upserts. The count is taken under a lock on the user, so creates landing together cannot pass it.

## Operations

- **Admin → KV** (`/admin/kv`) browses every entry: filter by key substring, user, lobby, or global-only; create, edit, delete, and bulk-delete.
- The admin HTTP API mirrors it: `PUT` / `DELETE /api/v1/admin/kv` upsert and delete by key + scope, and `/api/v1/admin/kv/entries` lists and manages entries by row id.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.KV`](https://docs.gamend.org/Gamend.KV.html) - the functions a plugin calls, with their signatures and docs.
