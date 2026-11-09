---
icon: hero-scale-solid
---

# Ratings

`Gamend.Rating` computes skill ratings: Elo and Glicko-2, for duels, teams and free-for-alls, and how wide a gap a matcher accepts as a player waits. It only computes. Your game says when a match counts and where the numbers live.

## One finished match

Give `settle/3` each team's ratings and its place, 1 being the best. Equal places are a draw, and a duel or a free-for-all is teams of one.

```elixir
alias Gamend.Rating

teams = [[Rating.new()], [Rating.new(rating: 1720, deviation: 90)]]

[[winner], [loser]] = Rating.settle(teams, [1, 2])

winner.rating    # 1815.1: a new player beat a proven one, so a big jump
loser.rating     # 1698.4: already sure of this one, so a small step
```

Each player is rated against every other team taken as one opponent. Glicko-2 is the default because it knows how sure it is of a rating, so a new player moves fast and a veteran slowly. `algorithm: :elo` uses Elo instead.

| Function | Answers |
|---|---|
| `new/1` | A rating, unrated unless `:rating`, `:deviation` or `:volatility` is given |
| `settle/3` | A finished match of any shape, as the teams updated |
| `glicko2/3` | One player after a list of `{opponent, score}`; no games is an idle period, and the deviation grows |
| `elo/4` | `{new_a, new_b}` for two plain numbers |
| `expected/2` | The chance the first beats the second |
| `band/2` | The rating gap to accept after waiting so long |
| `dump/1`, `load/1` | A rating as a map of plain values, and back |

## Storing a rating

A leaderboard with the `set` operator is a rating table with a ranking for free: the score is the number players see, and the record's metadata keeps the rest. A `key` per mode rates each mode on its own.

```elixir
Leaderboards.submit_score(board.id, user_id, round(rating.rating), Rating.dump(rating), key: mode)

{:ok, record} = Leaderboards.get_user_record(board.id, user_id, key: mode)
rating = Rating.load(record.metadata)
```

Read, compute and write under `Gamend.Lock.serialize/3` if a player can finish two rated matches at once. Rate on the server only, from a verdict your game trusts: no client sends its own result.

## Matching on skill

Keep a coarse band in `match_params` and compare the exact rating in the matcher. `band/2` widens the gap with the wait, so an unusual rating still finds a match. It starts at `:base` (100), grows by `:per_second` (20) and stops at `:max` (1000).

```elixir
@mode "mode"
@ranked "ranked"

@impl true
def matchmaking_form_matches(%{@mode => @ranked}, tickets) do
  tickets
  |> Enum.map(&{rating_of(&1.user), &1})
  |> Enum.sort_by(&elem(&1, 0))
  |> Enum.chunk_every(2, 2, :discard)
  |> Enum.filter(fn [{a, ticket}, {b, _}] -> abs(a - b) <= Rating.band(waited_ms(ticket)) end)
  |> Enum.map(fn [{_, a}, {_, b}] -> [a, b] end)
end
```

See [Matchmaking](/docs/matchmaking) for the queue, and `modules/plugins_examples/example_hook` for all of this in one plugin: the rating board, the matcher, and the update when a ranked lobby ends. The plugin SDK carries the real `Gamend.Rating`, so it runs in a plugin's own tests, and a [GDScript hook](/docs/gdscript-hooks) calls it as `Rating.settle(teams, places)`.
