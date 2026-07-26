---
icon: hero-chart-bar
---

# Leaderboards

Leaderboards allow you to rank players based on scores. Scores are submitted server-side only (authoritative mode) ensuring fair competition. Each leaderboard acts as a season with optional start/end dates.

## Key Concepts

- **Sort Order:** `desc` (highest first) or `asc` (lowest first)
- **Operators:** `set` (replace), `best` (only if better), `incr` (add), `decr` (subtract)
- **Seasons:** Each leaderboard is a season. Set `ends_at` to mark as ended
- **Metadata:** Store additional JSON data on leaderboards and individual records

## Submitting scores

Scores are server-authoritative: there is no client endpoint to write one, so
a plugin calls the context directly. Ids are UUIDv7 strings.

```elixir
{:ok, board} =
  GameServer.Leaderboards.create_leaderboard(%{
    slug: "weekly_score_2024_w48",
    title: "Weekly High Scores",
    sort_order: :desc,
    operator: :best,
    starts_at: ~U[2024-11-25 00:00:00Z],
    metadata: %{"prize" => "Gold Badge"}
  })

# Resolve the live season by slug, then submit against its id.
if board = GameServer.Leaderboards.get_active_leaderboard_by_slug("weekly_score_2024_w48") do
  GameServer.Leaderboards.submit_score(board.id, user_id, 9500, %{"level" => 15})
end
```

Reading back:

```elixir
GameServer.Leaderboards.list_records(board.id, page: 1, page_size: 25)
GameServer.Leaderboards.get_user_record(board.id, user_id)
GameServer.Leaderboards.list_records_around_user(board.id, user_id, limit: 5)
GameServer.Leaderboards.end_leaderboard(board)
```

## Icons

Leaderboards carry an optional `icon_url` (admin form or API). When unset,
the web UI shows the shared default leaderboard icon and the API returns
`""` so game clients can apply their own.

## Best Practices

- Use descriptive slugs like `weekly_score_2024_w48` or `season_3_pvp`
- Set `starts_at` for scheduled leaderboards
- Use `operator: :best` for high score boards, `:incr` for cumulative
- Store extra context in `metadata` (quests, levels, etc.)
- Create new leaderboards for new seasons instead of resetting
- Use `/records/around/:user_id` to show player context in the rankings

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Leaderboards`](https://appsinacup.com/game_server/GameServer.Leaderboards.html) - the functions a plugin calls, with their
  signatures and docs.
