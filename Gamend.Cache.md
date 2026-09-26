# `Gamend.Cache`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/cache.ex#L1)

Application cache backed by Nebulex.

This cache uses a 2-level (near-cache) topology via
`Nebulex.Adapters.Multilevel`:

- L1: local in-memory cache (`Gamend.Cache.L1`)
- L2: either Redis (`Gamend.Cache.L2.Redis`) or a partitioned topology
  (`Gamend.Cache.L2.Partitioned`), selected via runtime config.

# `bump_version`

```elixir
@spec bump_version(term()) :: :ok
```

Increments the version counter at `key` and broadcasts the bump so every
other app instance increments its local copy too (see `Gamend.Cache.Sync`).

Version-keyed caches embed the counter in their data keys, so any change to
the counter forces a fresh recompute on the next read. Remote nodes apply a
bump rather than a delete: a delete would re-seed their counter at 1, which
can collide with version values whose data entries are still inside a TTL,
while a bump is monotonic per node.

# `cached`

```elixir
@spec cached(term(), keyword(), (-&gt; term())) :: term()
```

Cache-through helper: returns the cached value for `key`, or computes and
caches the result of `fun`.

Cached `nil` results are honored — `fun` only runs on a real cache miss.

## Options

- `:ttl` — time-to-live in milliseconds

# `count_all`

# `count_all`

# `count_all!`

# `count_all!`

# `decr`

# `decr`

# `decr!`

# `decr!`

# `delete`

# `delete`

# `delete!`

# `delete!`

# `delete_all`

# `delete_all`

# `delete_all!`

# `delete_all!`

# `expire`

# `expire`

# `expire!`

# `expire!`

# `fetch`

# `fetch`

# `fetch!`

# `fetch!`

# `fetch_or_store`

# `fetch_or_store`

# `fetch_or_store!`

# `fetch_or_store!`

# `get`

# `get`

# `get!`

# `get!`

# `get_all`

# `get_all`

# `get_all!`

# `get_all!`

# `get_and_update`

# `get_and_update`

# `get_and_update!`

# `get_and_update!`

# `get_or_store`

# `get_or_store`

# `get_or_store!`

# `get_or_store!`

# `has_key?`

# `has_key?`

# `in_transaction?`

# `in_transaction?`

# `inclusion_policy`

A convenience function to get the cache inclusion policy.

# `incr`

# `incr`

# `incr!`

# `incr!`

# `info`

# `info`

# `info!`

# `info!`

# `invalidate`

```elixir
@spec invalidate(term()) :: :ok
```

Deletes `key` on this node (all cache levels) and broadcasts the deletion so
every other app instance evicts the key from its local L1
(see `Gamend.Cache.Sync`).

Use this instead of `delete/1` whenever a stale read would be *incorrect*
rather than merely briefly outdated — e.g. cached user structs that gate
authentication (`token_version`) or account state (`is_activated`).

# `invalidation_topic`

```elixir
@spec invalidation_topic() :: String.t()
```

PubSub topic that `invalidate/1` broadcasts on.

# `put`

# `put`

# `put!`

# `put!`

# `put_all`

# `put_all`

# `put_all!`

# `put_all!`

# `put_new`

# `put_new`

# `put_new!`

# `put_new!`

# `put_new_all`

# `put_new_all`

# `put_new_all!`

# `put_new_all!`

# `register_event_listener`

# `register_event_listener`

# `register_event_listener!`

# `register_event_listener!`

# `replace`

# `replace`

# `replace!`

# `replace!`

# `stream`

# `stream`

# `stream!`

# `stream!`

# `take`

# `take`

# `take!`

# `take!`

# `touch`

# `touch`

# `touch!`

# `touch!`

# `transaction`

# `transaction`

# `ttl`

```elixir
@spec ttl() :: pos_integer()
```

How long a cached entity is kept, in milliseconds (`cache.ttl_ms`). Every
entity cache uses it; the few entries with a deliberate lifetime of their own
(leaderboard records, analytics) do not.

# `ttl`

# `ttl`

# `ttl!`

# `ttl!`

# `unregister_event_listener`

# `unregister_event_listener`

# `unregister_event_listener!`

# `unregister_event_listener!`

# `update`

# `update`

# `update!`

# `update!`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
