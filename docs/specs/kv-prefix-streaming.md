# KV prefix queries and streaming

Goal: make "all of this user's entries under `word_stats:`" a single indexed,
cursor-paged query instead of a substring `LIKE` behind offset pagination that
a plugin has to loop over by hand.

## Why core

`GameServer.KV.list_entries/1` is an **admin list endpoint** that plugins have
been pressed into using as a data access path. Three problems, all structural:

1. **`:key` is a substring filter, not a prefix.** `%key%` cannot use an index,
   so every scoped read is a sequential scan of `kv_entries`, and
   `key: "map_state:"` also matches `legacy_map_state:` — a correctness trap,
   not just a slow one.
2. **Offset pagination over a mutable set.** Ordering is `updated_at desc`, and
   reading a page *touches nothing* but writing does — so a set being written to
   while it is being paged can skip and repeat rows. Polyglot's
   `GameCommon.list_user_entries/3` loops pages until a short one comes back;
   under concurrent writes that loop is not guaranteed to see every row.
3. **Cache thrash.** Each page is cached under a key that includes the page
   number and a scope version, and any write to that scope bumps the version —
   so a full walk of N pages populates N cache entries that are invalidated
   before the next walk uses them.

The workaround exists in the wild (`list_user_entries/3`, plus a comment
explaining that a single fixed page "silently truncates once a user accumulates
more rows than one page" — which is the bug being routed around). Every game
with per-entity KV keys writes it again.

## API

```elixir
KV.list_by_prefix("word_stats:", user_id: user_id, limit: 200, after: cursor)
#=> {entries, next_cursor | nil}

KV.stream_by_prefix("word_stats:", user_id: user_id)   # Stream, keyset-paged
KV.count_by_prefix("word_stats:", user_id: user_id)
KV.delete_by_prefix("map_state:", user_id: user_id)    # returns count
```

- **Prefix, not substring.** `where: like(e.key, ^(escape_like(prefix) <> "%"))`
  using the repo's existing `escape_like` helper and `ESCAPE '\'` (the
  cross-dialect pattern already in use), so `_` and `%` in a game's keys are
  literal.
- **Keyset cursor, not offset.** Ordered by `key` (with `id` as tiebreaker),
  cursor is the last key seen: `where: e.key > ^cursor`. Stable under concurrent
  writes, and the same index serves the ordering and the filter.
  `updated_at desc` stays the ordering of the admin list; it is the wrong one
  for a walk.
- **`stream_by_prefix/2` bypasses the cache.** A full walk is a bulk read whose
  results are stale the moment they land; caching each page evicts entries that
  short reads actually benefit from. Documented, not silent.
- **`delete_by_prefix/2`** is the operation every game hand-rolls for cleanup
  (and `delete_user_lobby_entries/2` already proves core needs the shape). One
  batched `DELETE`, cache invalidated per scope once, `kv_deleted` broadcasts
  emitted for the deleted keys.

Scope options are the existing ones — `:user_id`, `:lobby_id`, `:global_only` —
so prefix queries compose with the scoping that already exists rather than
inventing a second vocabulary.

## Index

Prefix matching on `key` within a scope wants a leading-column-ordered index.
The existing unique indexes are `(user_id, key)` (where user present),
`(lobby_id, key)` and `(key)` (where both null) — which is exactly the right
shape for `user_id = ? AND key LIKE 'prefix%'` on both adapters, since a
left-anchored `LIKE` is index-usable in SQLite and in Postgres for the default
collation via `text_pattern_ops`.

So: **no new index on SQLite**; one `text_pattern_ops` index on Postgres if the
deployment's collation is not `C`, added in the same migration and verified with
`EXPLAIN` in the test suite's Postgres run. The plain `index(:kv_entries, [:key])`
covers global-scope prefix scans.

## Limits and safety

- `limit` defaults to 200, capped by `Limits.get(:max_kv_page_size)` (new, 1000).
- `stream_by_prefix/2` pages at the same cap; it is not an unbounded `Repo.all`.
- Prefix must be non-empty for `delete_by_prefix/2` — deleting everything under
  `""` is never what anyone meant, and returns `{:error, :prefix_required}`.
- These are server-side APIs. **No client endpoint**: `PUT /kv` is admin-only
  today and prefix scans are not something a client should ever drive. Plugins
  call them from hooks.

## Admin

The admin KV page's key filter becomes prefix-aware: a trailing `*` means
prefix (indexed), anything else stays the substring behaviour operators expect
from a search box. The page also gains a per-prefix count so an operator can see
that `word_stats:` is 40 000 rows before deciding to prune it — which is what
makes the retention conversation possible at all.

## Alternatives considered

- **Keep offset paging, just add a real prefix filter.** Fixes the index and the
  false matches, leaves the skip/repeat window under concurrent writes. Keyset
  costs one column in the cursor and removes the whole class.
- **A separate `kv_namespaces` table / a `namespace` column.** Cleaner in theory
  — a real scope column instead of a naming convention — but it is a migration
  over every existing key, a breaking change to every game's key strings, and
  prefix keys are already the established convention (`word_stats:<a>|<b>`,
  `map_state:<course>:<lesson>`). Not worth the break.
- **Expose Ecto queries to plugins.** Plugins already have `Repo`, so this is
  possible today and is exactly what we do not want to encourage: it couples
  games to core's schema.
- **Cache the stream.** See above; a bulk walk is the wrong thing to cache.

## Definition of done (CONTRIBUTING)

- [ ] `list_by_prefix/2`, `stream_by_prefix/2`, `count_by_prefix/2`,
      `delete_by_prefix/2` on `GameServer.KV`, scoped by the existing options.
- [ ] Prefix uses escaped left-anchored `LIKE` with `ESCAPE '\'`; a key
      containing `%` or `_` matches literally (test).
- [ ] Keyset cursor ordered by `key`; a walk under concurrent writes returns
      every row exactly once (test on both adapters).
- [ ] `stream_by_prefix/2` documented as cache-bypassing; short reads still
      cached as today.
- [ ] `delete_by_prefix/2` batches, invalidates the scope cache once, broadcasts
      deletions, and refuses an empty prefix.
- [ ] Migration adds the Postgres `text_pattern_ops` index; applies on SQLite
      **and** `GAMEND_DB_ADAPTER=postgres`; `EXPLAIN` asserts index use in the
      Postgres run.
- [ ] `max_kv_page_size` declared on the `Limits` settings provider
      (`GAMEND_LIMITS_MAX_KV_PAGE_SIZE`); `.env.example` regenerated with
      `mix gamend.settings.env_example`.
- [ ] Admin KV page: `*` prefix search and per-prefix counts; API parity;
      `admin_pages_render_test`.
- [ ] Docs (Key-Value page) show the prefix convention and the stream API;
      `api_spec.ex`; CHANGELOG; i18n; SDK mirrors the new functions,
      `mix gen.sdk` clean.
- [ ] Polyglot's `GameCommon.list_user_entries/3` and its page loop are deleted
      in favour of `stream_by_prefix/2` (tracked in that repo).
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; example plugin
      warning-free.
