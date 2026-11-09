# `Gamend.DemoSeed`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/demo_seed.ex#L1)

Fills the database with enough demo data to exercise pagination and the
list/detail pages at realistic sizes.

Everything is namespaced with a `demo-seed` prefix so `--clean` can remove it
again without touching real data.

## Usage

`mix demo.seed` in a checkout, `gamend demo.seed` from a release, with the
same arguments:

    mix demo.seed                       # all sets, 1000 rows each
    mix demo.seed --count 250           # smaller run
    mix demo.seed --only leaderboard    # one set (comma-separated)
    mix demo.seed --only group,tournament
    mix demo.seed --clean               # remove everything this task created

## Sets

  * `leaderboard` — a leaderboard with N scored records
  * `group`       — a public group with N members
  * `tournament`  — a tournament with N registered entries, still open
  * `result` — finished and open plays for `/admin/results`, a dozen per
    player for the first 12 players, regardless of `--count` (this set is
    about having something to read, not volume)
  * `quest` — a daily, an auto-claim achievement, a chained follow-up and a
    twelve-member group that lists as one card, with per-user progress in
    every state (including claimable rows), and a code-only quest with a
    page of generated codes and the shared code `SPRING-GIFT`
  * `ready_check` — one check per seeded lobby in every outcome (open,
    passed, timed out, declined), also capped at 12
  * `chat_moderation` — a blocklist across every severity and match mode, a
    report queue deep enough to page through (every status, some filter-filed,
    some resolved) and mutes in every scope, including expired ones

The volume sets, one per admin list, sized from N:

  * `kv` — a profile row per player plus N/10 global keys (`/admin/kv`)
  * `notification` — one per player, and N/10 more for the first player
    (`/admin/notifications`, `/notifications`)
  * `analytics` — 2N events over 90 days, a few activity days per player,
    daily counters for a year (`/admin/analytics/*`)
  * `economy` — a wallet per player, 2N ledger entries, N/100 of them the
    first player's (`/admin/economy`)
  * `payment` — N/10 purchases, each with its entitlement (`/admin/payments`)
  * `report` — N/10 page reports over 500 pages (`/admin/reports`)
  * `friend` — a friendship per player, N/100 friends for the first player
    (`/admin/friends`)
  * `session` — a session token per player (`/admin/sessions`)
  * `lobby` — N/10 lobbies (`/admin/lobbies`)
  * `ban` — N/100 account and IP bans (`/admin/bans`)
  * `inventory` — two items per player (`/admin/economy`)

The first player is the heavy one: `mix demo.bench` signs in as them for the
player pages, so their lists are the long ones.

The `result` set goes through `Gamend.Results`, so what you see is shaped
exactly like a game's writes, then moves each play back in time so the list
spans the last weeks.

Seeded runs keep their lobby row so `--clean` can find them again. Real
completed runs outlive theirs, since a lobby is deleted when its last member
leaves.

All sets share one pool of N anonymous device accounts, so the same players
appear across them (as they would in a real deployment).

Rows are inserted in bulk rather than through the contexts: this is about
volume, not about exercising business rules, and 1000 individual writes on
SQLite is slow. Rows are streamed in statements of up to 30,000 parameters,
four at a time on Postgres, so a million rows a set fits in memory and takes
seconds per set. The cache is flushed afterwards so pages read the new rows,
and Postgres re-analyses the tables so the planner sees their new size.

# `analyze_tables`

```elixir
@spec analyze_tables() :: :ok
```

Re-analyses the tables after a bulk load (Postgres; nothing on SQLite).

# `bench_context`

```elixir
@spec bench_context() :: %{
  admin_token: binary(),
  player_token: binary(),
  params: map()
}
```

What `mix demo.bench` signs in with and links to: a session token for an
admin (created on first call as `demo-seed-admin`, removed by `--clean`)
and one for the heavy player (the first, whose lists are the long ones),
plus the ids of the seeded pages. Raises `ArgumentError` before a seed.

# `insert_rows`

```elixir
@spec insert_rows(Enumerable.t(), module()) :: non_neg_integer()
```

For a host's own seed: streams `rows` into `schema` the way every set here
does (statements under the bind-parameter limit, four at once on
Postgres) and answers how many went in. `analyze/0` after a bulk load.

# `player_ids`

```elixir
@spec player_ids(pos_integer() | nil) :: [Ecto.UUID.t()]
```

For a host's own seed (`mix polyglot.demo.seed`): the demo players' ids in
order, the heavy one first, `count` of them (every one by default). Empty
before `demo.seed` has run.

# `run`

```elixir
@spec run([String.t()]) :: :ok
```

Seeds (or with `--clean` removes) the demo data. Takes the same arguments as
`mix demo.seed`; the application must already be running. Raises
`ArgumentError` on an unknown set.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
