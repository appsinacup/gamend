# `Gamend.Analytics`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics.ex#L1)

The one place aggregate numbers come from. Four families:

* **Activity & retention** — DAU / WAU / MAU, new users per day, strict
  D1 / D7 / D30 cohort retention, payer conversion. Derived from
  `user_activity_days` (one row per user per UTC day seen, written by
  `record_activity/2` from the `last_seen_at` touches in `Gamend.Accounts`),
  `users.inserted_at` for cohorts and `purchases` for payers.
* **Snapshot** — `snapshot/0`: every context's live counters (players,
  lobbies, parties, quests, signaling, matchmaking, tournaments) composed
  once and cached, so the public stats page, the admin index and the
  `/api/v1/stats` endpoint show the same numbers instead of each calling
  six modules.
* **Economy flow** — `economy_flow/2`: coins granted and spent per day per
  ledger `reason`, straight from `ledger_entries`.
* **Daily counters** — `count/3` + `counts/2`: named per-day counters for
  events that have no table of their own (a level finished, a start blocked
  by empty hearts). The game picks the keys; the engine sums them.
  `families/3` reads them back grouped: a base key with its dimensions.
* **Events** — `track/3`: one call that counts (the name, and the name per
  dimension) AND, for an account, keeps the row — who, when, every field —
  in `analytics_events`. A visitor's event is counted only. The counters answer "how many" forever; the rows
  answer what a sum cannot: how many distinct people did a thing
  (`feature_summary/1`: DAU / WAU / MAU, first-timers and D1 / D7 / D30
  per feature), in what order, with what else. Writes are gathered by
  `Gamend.Analytics.Buffer` and landed in batches.

Days are UTC, like every other period boundary on the server. "D7" means
*seen on the 7th day after the registration day*, not "seen at any point in
the first week" — the classic strict definition, so numbers compare with
the ones stores and ad networks report.

Reads are cheap enough for a dashboard on a small database; the composed
views (`snapshot/0`, `dashboard_stats/0`) cache for a minute or a few.
Nothing here is exposed to players except through the operator-gated
public stats page.

# `rate`

```elixir
@type rate() :: float() | nil
```

# `activation`

```elixir
@spec activation(Date.t(), keyword()) :: map() | nil
```

Activation, when the host declares it (`Catalog.overview/0`'s
`activation`): of the accounts made in the 30 full days before `today`
(from `retention_since` on; today's are still in their first day), how
many reported one of its events on the day they were made, and D1 for
those that did and those that did not (cohorts whose next day is over:
before yesterday). `%{label, new, activated, rate,
d1_activated, d1_activated_cohort, d1_other, d1_other_cohort}`, or nil
with no activation declared. Options: `segment:` (`segments/0`).

# `active_days`

```elixir
@spec active_days(Date.t(), keyword()) :: [map()]
```

The accounts seen in the 30 days ending on `today`, by how many of those
days each was seen: `[%{label, min, max, users}]`, one day first. Most of
a young game's MAU is seen once; this says how many came back at all.
Options: `segment:` (`segments/0`).

# `active_users`

```elixir
@spec active_users(Date.t(), Date.t(), keyword()) :: non_neg_integer()
```

Distinct users seen on any day in `from..to` (inclusive, UTC dates).
Options: `segment:` (`segments/0`).

# `count`

```elixir
@spec count(String.t(), pos_integer(), DateTime.t()) :: :ok
```

Adds `n` to the counter `key` for the UTC day of `now`. Gathered by
`Gamend.Analytics.Buffer` and written as one upsert per `(key, day)` at the
next flush (within `flush_ms`, 10 s); written through at once where the
buffer is off (tests) or not running. Cheap enough for any path.

Keys are dotted, game-owned strings up to 128 chars;
put a dimension after a colon (`"level.started.lang:ja"`) so `counts/2`
can pull a whole family by prefix and `families/3` can group it. Never
raises; a bad key is dropped with a warning.

# `count_totals`

```elixir
@spec count_totals(String.t(), pos_integer(), Date.t()) :: [{String.t(), integer()}]
```

Totals of `counts/3` per key over the window, largest first.

# `counts`

```elixir
@spec counts(String.t(), pos_integer(), Date.t()) :: %{
  required(String.t()) =&gt; %{required(Date.t()) =&gt; integer()}
}
```

Per-day values of one counter or a prefix family over the last `days` days
ending on `today`, as `%{key => %{Date => count}}`. `key` may end in `*` to
match a prefix (`"level.started.lang:*"`).

# `daily_series`

```elixir
@spec daily_series(pos_integer(), Date.t(), keyword()) :: [map()]
```

One row per UTC day for the last `days` days ending on `today`, oldest
first: `%{day, active, new_active, returning, wau, mau, stickiness,
new_users, d1, d7, d30}`. `new_active` are the accounts made that day and
seen on it, `returning` the rest of `active`. `wau` / `mau` are the
distinct users of the 7 / 30 days ending on that day, and `stickiness` is
`active ÷ mau` of that day (nil today, whose `active` is partial). A
retention rate is `nil` when the cohort is
empty, the horizon day is not over yet, or the cohort is older than
`retention_since` (`Gamend.Analytics.Catalog.overview/0`). Options:
`segment:` (`segments/0`).

# `dashboard_stats`

```elixir
@spec dashboard_stats() :: map()
```

`summary/0` cached for a few minutes, for the admin index.

# `dau`

```elixir
@spec dau(Date.t(), keyword()) :: non_neg_integer()
```

Daily active users on `day` (default: today, UTC).

# `days_seen`

```elixir
@spec days_seen(Ecto.UUID.t()) :: non_neg_integer()
```

On how many different days `user_id` was seen, ever.

# `economy_flow`

```elixir
@spec economy_flow(pos_integer(), keyword()) :: [map()]
```

Currency granted and spent per UTC day per ledger `reason` over the last
`days` days: `[%{day, currency, reason, granted, spent, entries}]`, newest
first. `granted`/`spent` are positive integers (spent is the absolute
value of negative deltas). Options: `:currency` to filter.

# `economy_totals`

```elixir
@spec economy_totals(pos_integer(), keyword()) :: [map()]
```

`economy_flow/2` collapsed over the window: one row per `{currency,
reason}` with `granted`, `spent`, `net`, sorted by absolute net.

# `families`

```elixir
@spec families(String.t(), pos_integer(), Date.t()) :: [map()]
```

The counters of the last `days` days grouped by family, largest first:
`[%{key, total, by_day, dims}]`, where `key` is the bare counter
(`"web.game.finished"`), `by_day` its `%{Date => n}`, and `dims` every
dimension written under it — `%{"lang" => [{"ro", 120}, {"es", 80}]}` from
the keys `web.game.finished.lang:ro` and `…lang:es` — each list largest
first. `prefix` as in `counts/3` (`"web.*"`, or one key).

# `feature_summary`

```elixir
@spec feature_summary(Date.t(), keyword()) :: [map()]
```

Every event name of the last 60 days as a feature,
with what `summary/1` says of the whole site: `[%{name, dau, wau, mau,
stickiness, events_7d, new_7d, new_30d, d1, d7, d30}]`, largest MAU first.

Active = at least one event of that name that day (only an account's
events are kept as rows). "New" = first event of the name in the window (a
player back after 60 quiet days reads as new). D1 / D7
/ D30 are pooled over the first-day cohorts old enough to have reached the
horizon, as `summary/1` pools sign-up cohorts.

Options: `segment:` (`segments/0`, default `:all`).

# `flush`

```elixir
@spec flush() :: {non_neg_integer(), non_neg_integer()}
```

Writes everything `Gamend.Analytics.Buffer` has gathered, now, in the caller's process.

# `funnel`

```elixir
@spec funnel(pos_integer(), Date.t()) :: [map()]
```

The host's funnel (`Catalog.overview/0`) over the `days` days ending on
`today`: `[%{label, source, unit, value, of_previous}]`, `unit` `:events`
for a counter's total (a visitor counts there, each time) and `:people`
otherwise, `of_previous` the step's share of the one before: nil first,
and nil where the unit changes (events and people do not divide).

# `mau`

```elixir
@spec mau(Date.t(), keyword()) :: non_neg_integer()
```

Monthly active users: distinct users seen in the 30 days ending on `day`.

# `money`

```elixir
@spec money(pos_integer(), Date.t()) :: map()
```

Money over the `days` days ending on `today`, for the Overview: checkouts
opened, purchases fulfilled, checkouts refused or failed and webhook
deliveries that failed or were refused (`Gamend.Payments.Counters`),
revenue by currency (completed production purchases, minor units),
payers, and the free trials when the host names their keys
(`Catalog.overview/0`'s `trial_keys`): `%{started, running, taken,
decided, paid, conversion}`, `paid` the people with a completed purchase
after their trial began, `decided` those whose trial ended or who paid,
and `conversion` paid ÷ decided.

# `new_users`

```elixir
@spec new_users(Date.t(), Date.t()) :: non_neg_integer()
```

Accounts created on any UTC day in `from..to` (inclusive).

# `payers_since`

```elixir
@spec payers_since(Date.t(), keyword()) :: non_neg_integer()
```

Distinct users with a completed purchase since `from` (UTC date, inclusive).
Options: `segment:` (`segments/0`).

# `people_by_dimension`

```elixir
@spec people_by_dimension(String.t(), String.t(), pos_integer(), Date.t(), keyword()) ::
  [map()]
```

One feature broken down by one of its dimensions over the last `days`
days: `[%{value, people, events}]`, people = distinct signed-in users,
largest first; a row without the dimension is `"none"`. The dimensions a
feature has are the keys of its family's `dims` (`families/3`). Options:
`segment:` (`segments/0`).

    people_by_dimension("web.game.started", "game")
    #=> [%{value: "hangman", people: 41, events: 212}, …]

# `recent_events`

```elixir
@spec recent_events(pos_integer()) :: [Gamend.Analytics.Event.t()]
```

The last `limit` events, newest first.

# `record_activity`

```elixir
@spec record_activity(Ecto.UUID.t(), DateTime.t()) :: :ok
```

Records that `user_id` was seen on the UTC day of `now`. Idempotent; the
common case (already recorded today) is a single cache read. Never raises —
a missing user (deleted mid-request) is a silent no-op, like the
`last_seen_at` touch this rides along with.

# `segment`

```elixir
@spec segment(term()) :: Gamend.Analytics.Segment.t()
```

A segment from a request parameter; anything unknown is `:all`.

# `segments`

```elixir
@spec segments() :: [Gamend.Analytics.Segment.t()]
```

Every segment the people numbers split by (`Gamend.Analytics.Segment`).

# `snapshot`

```elixir
@spec snapshot() :: map()
```

Every context's live counters in one map, cached for a minute:

    %{
      players: %{players_online, players_total, players_offline, players_in_lobbies, players_in_parties},
      activity: %{dau, wau, mau, new_users_1d, new_users_7d, new_users_30d},
      lobbies: %{lobbies_total, by_state, spectators},
      parties: %{parties_active, players_in_parties},
      quests: %{quests_total, completed, claimed},
      signaling: %{rooms_enabled, rooms_active, peers_connected},
      matchmaking: %{queued, queues},
      tournaments: %{tournaments, entries, matches}
    }

Everything in it is safe to show publicly (the stats page is opt-in via
`:public_stats`); `matchmaking` is the already-public subset. Consumers
read this rather than calling the contexts, so the same number cannot
drift between two pages.

# `summary`

```elixir
@spec summary(Date.t(), keyword()) :: map()
```

Headline numbers as of `today`: DAU (today so far) / WAU / MAU,
stickiness (`dau_avg`, the average DAU of the 30 full days before today,
÷ `stickiness_mau`, the accounts seen in those same 30 days: today is
partial until midnight, and a shorter DAU window than the MAU's reads high
while the site grows), new users
in the last 7 and 30 days, D1 / D7 / D30 pooled over every cohort of the
last 60 days whose horizon day is over and not older
than `retention_since` (`Catalog.overview/0`), each
with its pool's size (`d1_cohort`, …), and payer conversion (distinct users
with a completed purchase in the last 30 days ÷ MAU). Options: `segment:`
(`segments/0`).

# `track`

```elixir
@spec track(String.t(), map(), keyword()) :: :ok
```

Records that something happened: `name` is counted for the day (`count/3`),
once more per DIMENSION (`name.lang:ro`), and, when it has a user, the
whole event — `dims`, `user_id`, the moment — is kept as a row in
`analytics_events`. One call, so a counter and its event can never
disagree.

An event with no user (a visitor, a webhook) is counted and never kept: a
row is there to say WHO, and a visitor has no id to say it with. On a site
crawlers read, they were nearly every row.

`name` is dotted `[a-z0-9_]`, up to 64 chars (`"web.game.finished"`).
`dims` is a map of the event's fields, atom or string keys of `[a-z0-9_]`:

  * a string, atom or boolean value is a **dimension**: a closed set the
    caller owns (a language code, a game, `practice | daily`), counted as
    its own key, so keep free text out of it;
  * an integer or float is a **measure** (a score, seconds): kept in the
    row, never counted;
  * `nil` is dropped.

Options: `user_id:` (nil for a visitor: counted only; nulled on the kept
row when the account is deleted), `at:` (default now). Buffered like `count/3`. Never raises: a bad
name or field is dropped with a warning, the rest is kept.

    Analytics.track("web.game.finished",
      %{game: "hangman", lang: "ro", mode: :daily, score: 7, total: 10},
      user_id: user_id)

# `trait_options`

```elixir
@spec trait_options(pos_integer(), Date.t()) :: [map()]
```

The host's traits (`Catalog.overview/0`'s `traits`) with the values the
event rows of the `days` days ending on `today` hold, most accounts first,
20 at most each: `[%{field, label, values: [value]}]`, a trait with no
value left out. What a page offers to filter accounts by
(`Segment.with_trait/2`). Cached for a few minutes.

# `users_seen_on`

```elixir
@spec users_seen_on(pos_integer()) :: [Ecto.UUID.t()]
```

The accounts seen on `min_days` different days or more, ever (their
`user_activity_days` rows): a host's "regular players", asked something
only they can answer.

# `wau`

```elixir
@spec wau(Date.t(), keyword()) :: non_neg_integer()
```

Weekly active users: distinct users seen in the 7 days ending on `day`.

# `weekly_cohorts`

```elixir
@spec weekly_cohorts(Date.t(), keyword()) :: [map()]
```

Retention by sign-up week, the last 8 weeks (Monday
first) from `retention_since` on, newest first: `[%{week, from, size,
cells}]`, each cell `%{week: k, users, rate}` the share of the week's
accounts seen in their own week k after sign-up (days 7k to 7k + 6 after
their sign-up day). A cell is `rate: nil` until every account of the week
has lived through it. Options: `segment:` (`segments/0`).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
