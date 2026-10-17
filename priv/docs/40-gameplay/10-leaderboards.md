---
icon: hero-chart-bar
---

# Leaderboards

Leaderboards allow you to rank players based on scores. Scores are submitted server-side only (authoritative mode) ensuring fair competition. Each leaderboard acts as a season with optional start/end dates.

## Key concepts

- **Sort Order:** `desc` (highest first) or `asc` (lowest first)
- **Operators:** `set` (replace), `best` (only if better), `incr` (add), `decr` (subtract)
- **Seasons:** Each leaderboard is a season. Set `ends_at` to mark as ended
- **Metadata:** Store additional JSON data on leaderboards and individual records

## Submitting scores

Scores are server-authoritative: there is no client endpoint to write one, so
a plugin calls the context directly. Ids are UUIDv7 strings.

```elixir
{:ok, board} =
  Gamend.Leaderboards.create_leaderboard(%{
    slug: "weekly_score_2024_w48",
    title: "Weekly High Scores",
    sort_order: :desc,
    operator: :best,
    starts_at: ~U[2024-11-25 00:00:00Z],
    metadata: %{"prize" => "Gold Badge"}
  })

# Resolve the live season by slug, then submit against its id.
if board = Gamend.Leaderboards.get_active_leaderboard_by_slug("weekly_score_2024_w48") do
  Gamend.Leaderboards.submit_score(board.id, user_id, 9500, %{"level" => 15})
end
```

Reading back:

```elixir
Gamend.Leaderboards.list_records(board.id, page: 1, page_size: 25)
Gamend.Leaderboards.get_user_record(board.id, user_id)
Gamend.Leaderboards.list_records_around_user(board.id, user_id, limit: 5)
Gamend.Leaderboards.end_leaderboard(board)
```

## Many rankings on one board

A record is unique per user (or label) **and key**, and every read ranks within
one key (`""` by default). So one board can keep a best per player for each
set of settings, instead of a board per set:

```elixir
key = "match|60|es_es"

Gamend.Leaderboards.submit_score(board.id, user_id, 23, %{"game" => "match", "lang" => "es_es"},
  key: key
)

Gamend.Leaderboards.list_records(board.id, key: key)
Gamend.Leaderboards.get_user_record(board.id, user_id, key: key)

# Across keys: every row whose metadata matches, each player's best once.
Gamend.Leaderboards.list_records(board.id,
  key: :all,
  meta: %{"game" => "match"},
  best_per_user: true
)
```

Make the key the finest grain a reader may want: a coarser view is a `meta:`
filter over keys, a finer one cannot be made after the fact.

## Hidden boards

`hidden: true` keeps a board out of the public listings (`/leaderboards`, the
API index, `list_leaderboards/1` and `list_leaderboard_groups/1` unless
`include_hidden: true`). It is still a board: scores submit and rank, and it
reads by id or slug. For a board a host shows on its own pages.

## Icons

Leaderboards carry an optional `icon_url` (admin form or API). When unset,
the web UI shows the shared default leaderboard icon and the API returns
`""` so game clients can apply their own.

## What works well

- Use descriptive slugs like `weekly_score_2024_w48` or `season_3_pvp`
- Set `starts_at` for scheduled leaderboards
- Use `operator: :best` for high score boards, `:incr` for cumulative
- Store extra context in `metadata` (quests, levels, etc.)
- Create new leaderboards for new seasons instead of resetting
- Use `/records/around/:user_id` to show player context in the rankings

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Leaderboards`](https://docs.gamend.org/Gamend.Leaderboards.html) - the functions a plugin calls, with their
  signatures and docs.
