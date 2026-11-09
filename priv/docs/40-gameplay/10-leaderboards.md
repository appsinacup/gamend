---
icon: hero-chart-bar-solid
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

Around one player, read off the rank index (the key is never ranked whole):

```elixir
{:ok, me} = Gamend.Leaderboards.get_user_record(board.id, user_id, key: key)
# The rows just ahead and just behind, nearest first, ranked from mine.
{above, below} = Gamend.Leaderboards.list_records_beside(board.id, me, above: 1, below: 1)
# The bottom of the board, in rank order: where a first score comes in.
Gamend.Leaderboards.list_records_last(board.id, key: key, limit: 3)
```

A guest's record (kept off a public board) reads the same: its rank is
where it would stand, and the rows behind it are numbered as if it did.

A game client reads the same rankings over the API: `key` on
`GET /api/v1/leaderboards/{id}/records`, `/records/around/{user_id}` and
`/records/me` picks one (left out, `""`). Two more reads go with it:

| Endpoint | Answers |
| --- | --- |
| `GET /api/v1/leaderboards/{id}/keys?prefix=match` | the board's keys, the values a filter offers (`list_keys/2`), as `{"data": {"keys": [...]}}` |
| `GET /api/v1/leaderboards/{id}/records/above?score=12&key=match&limit=3` | the listed records just ahead of a score, nearest first, with their ranks: who a player overtakes next (`list_records_above/3`) |

A board's `metadata.views` (tabs and filters, see `GamendWeb.LeaderboardViews`)
names which keys it holds. A guest is in no list, as on the website.

## All time

A `:best` board with seasons (a start or an end date, `all_time?/1`) also
has an all-time ranking: every board under its slug read as one, each
player's (or label's) best row of them, ranked per key. `all_time: true` on
`list_records/2`, `count_records/2`, `get_user_record/3` and `list_keys/2`
reads it, from any season's id.

Those rows live on a hidden board of their own, `<slug>__all_time`: a submit
to a season raises it as a `:best` submit does, an edited or deleted season
row reads its owner's best again, a deleted season refills it. So All time
reads like one board, indexed and cached. (Read from the seasons on every
request, it took a second a page at 100,000 rows.) It is made and filled the
first time it is asked for; `rebuild_all_time/1` refills it after rows were
written around `submit_score/5` (a bulk import, `mix demo.seed`). On
`/leaderboards/<slug>`
the board shows two tabs above its season, its length ("Monthly",
"Weekly", "Daily", else "Season") and All time (`?period=all`), the view's
tab and filters kept.

## Hidden boards

`hidden: true` keeps a board out of the public listings (`/leaderboards`, the
API index, `list_leaderboards/1` and `list_leaderboard_groups/1` unless
`include_hidden: true`). It is still a board: scores submit and rank, and it
reads by id or slug. For a board a host shows on its own pages.

## Guests

A host can list registered players only:
`config :gamend_core, Gamend.AccountRequired, [:leaderboards]`. A guest (no
email, no provider, `User.anonymous?/1`) keeps their records on a public
board, but no list, count, rank or key of it includes them; their own
`get_user_record/3` answers with `hidden: true`. A hidden board keeps its
guests, and `guests: true` lists them (the admin's view).

Each record says whether its player is a guest (`leaderboard_records.guest`),
and the database keeps it: a trigger sets it from the user on every insert
(a submit, a merge, the All time fill, a bulk seed), and another moves every
record of a user who gains their first identity or loses their last. So a
guest who registers is listed at once (after the 10 s record cache), and a
listed read filters the record alone, on its own partial rank index
(`NOT guest`). Joining every record to its user instead took 0.6 to 1.5 s
for a rank, a search or a count at a million records. A new identity column
on `users` needs those triggers made again (migration
`LeaderboardRecordsGuest`).

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
