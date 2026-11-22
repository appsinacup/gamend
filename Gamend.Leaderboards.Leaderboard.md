# `Gamend.Leaderboards.Leaderboard`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/leaderboards/leaderboard.ex#L1)

Ecto schema for the `leaderboards` table.

A leaderboard is a self-contained scoreboard that can be permanent or time-limited.
Each leaderboard has its own settings for sort order and score operator.

## Slug
The `slug` is a human-readable identifier (e.g., "weekly_kills") that can be reused
across multiple leaderboard instances (seasons). Use the slug to always target the
currently active leaderboard, or use the integer `id` for a specific instance.

## Hidden
A hidden board is ranked and read like any other — by id, by slug, its
records — but no public listing shows it (the leaderboards page, the API
index). A host that shows a board on its own pages hides it.

## Icon
`icon_url` is optional; when nil, clients show their default leaderboard
icon (the web UI uses `GamendWeb.Icons.default(:leaderboard)`).

## User metadata keys
`user_metadata_keys` names what of each player's `users.metadata` the
board's rows carry, read when the row is (`user_metadata/2`): a top-level
key (`"rank"`) or a dotted path into it (`"player.pass_level"`), so one
value goes out and the rest of its map stays private. The rows are
public, so a key named here is world-readable. Empty, the default, sends
none; `payments` is never sent.

## Sort Order
- `:desc` — Higher scores rank first (default)
- `:asc` — Lower scores rank first (e.g., fastest time)

## Operators
- `:set` — Always replace with new score
- `:best` — Only update if new score is better (default)
- `:incr` — Add to existing score
- `:decr` — Subtract from existing score

# `operator`

```elixir
@type operator() :: :set | :best | :incr | :decr
```

# `sort_order`

```elixir
@type sort_order() :: :desc | :asc
```

# `t`

```elixir
@type t() :: %Gamend.Leaderboards.Leaderboard{
  __meta__: term(),
  description: term(),
  ends_at: term(),
  hidden: term(),
  icon_url: term(),
  id: term(),
  inserted_at: term(),
  metadata: term(),
  operator: term(),
  records: term(),
  slug: term(),
  sort_order: term(),
  starts_at: term(),
  title: term(),
  updated_at: term(),
  user_metadata_keys: term()
}
```

# `active?`

Returns true if the leaderboard is currently active (not ended).

# `changeset`

Changeset for creating a new leaderboard.

# `ended?`

Returns true if the leaderboard has ended.

# `update_changeset`

Changeset for updating an existing leaderboard.
Does not allow changing slug, sort_order, or operator after creation.

# `user_metadata`

```elixir
@spec user_metadata(t(), term()) :: map()
```

What of `user`'s metadata the board's rows carry: the values at its
`user_metadata_keys`, each in its place (`"player.pass_level"` answers
`%{"player" => %{"pass_level" => 7}}`). A path the user has no value at
is left out. `%{}` for a board that names none, or no user.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
