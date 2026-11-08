# `Gamend.Rating`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/rating.ex#L1)

Skill ratings, computed: Elo and Glicko-2, for two players, teams and
free-for-alls, and the gap a matcher accepts as a player waits
(priv/docs/40-gameplay/32-ratings.md).

    teams = [[Rating.new()], [Rating.new()]]
    [[winner], [loser]] = Rating.settle(teams, [1, 2])

Pure: nothing here reads or writes. A game stores the numbers where it
likes; `dump/1` and `load/1` turn one into a map and back. The SDK carries a
copy of this module (`mix gen.sdk`).

# `score`

```elixir
@type score() :: number()
```

How a game went for a player: 1.0 a win, 0.5 a draw, 0.0 a loss.

# `t`

```elixir
@type t() :: %Gamend.Rating{deviation: float(), rating: float(), volatility: float()}
```

A player's skill: `rating`, how unsure it is (`deviation`, shrinks with
games, grows when idle) and how erratic the player is (`volatility`).

# `band`

```elixir
@spec band(non_neg_integer(), keyword()) :: number()
```

The rating gap a matcher accepts after waiting `waited_ms`: it starts at
`:base` (100), grows by `:per_second` (20) and stops at `:max` (1000), so
nobody waits forever for a perfect opponent.

# `dump`

```elixir
@spec dump(t()) :: %{required(String.t()) =&gt; float()}
```

A rating as a map of plain values, for KV, metadata or a leaderboard record.

# `elo`

```elixir
@spec elo(number(), number(), score(), keyword()) :: {float(), float()}
```

Elo for one game: `{new_a, new_b}` for ratings `a` and `b`, `score` being
how it went for `a`. `:k` is the most one game can move a rating (32).

# `expected`

```elixir
@spec expected(t() | number(), t() | number()) :: float()
```

The chance `a` beats `b`, between 0.0 and 1.0. Takes ratings or plain numbers.

# `glicko2`

```elixir
@spec glicko2(t(), [{t(), score()}], keyword()) :: t()
```

Glicko-2 for one rating period: `player` after `games`, a list of
`{opponent, score}`. No games means an idle period, and only the deviation
grows. `:tau` limits how fast volatility moves (0.5; 0.3 to 1.2 is usual).

# `load`

```elixir
@spec load(map() | nil) :: t()
```

The rating `dump/1` wrote. Nothing stored, or a field that is not a number, is unrated.

# `new`

```elixir
@spec new(keyword()) :: t()
```

A player's rating, unrated unless `:rating`, `:deviation` or `:volatility` is given.

# `settle`

```elixir
@spec settle([[t()]], [pos_integer()], keyword()) :: [[t()]]
```

One finished match of any shape: `teams` (a list of lists of `t/0`, a team
of one for a duel or a free-for-all) and each team's place in `places`, 1
the best and equal places a draw. Answers the teams, in order, updated.

Each player is rated against every other team taken as one opponent.
`:algorithm` is `:glicko2` (default) or `:elo`, with `:tau` and `:k` as in
those functions.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
