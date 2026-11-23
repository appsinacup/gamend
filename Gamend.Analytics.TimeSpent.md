# `Gamend.Analytics.TimeSpent`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/time_spent.ex#L1)

How long accounts spend in the game, worked out from what is already
stored: nothing is collected for it.

Every row an account leaves is a moment it was there: its analytics
events (`analytics_events`, an account's only), the start of each play
(`results.started_at`) and each thing that happened in one
(`result_events`, `started_at + elapsed_ms`). Sorted per account, the
time from one moment to the next is time spent when it is at most
`idle_seconds` (default 5 minutes); a longer gap is the account away, and
counts nothing. A declared span (`spans`: a test started and finished,
with nothing stored in between) counts up to `span_seconds` (default 2
hours) from its start to its end.

Each gap is filed under where the account was at its start: the AREA of
the earlier moment, and its DETAIL where there is one:

  * a play's moment: the area `results` (default `"plays"`), the detail
    the play's `kind` (a game);
  * an event named in `dim`'s list: the value of that field (`"section"`
    of a page view), passed through `areas`;
  * any other event: its catalogue group (`Gamend.Analytics.Catalog`),
    passed through `areas`.

So the numbers are a floor: the time after an account's last moment of a
visit (reading the last page, the end of a round) is not counted, and a
visitor with no account leaves no rows, so is in none of it. Days are
UTC days, as DAU is. The host says how its rows read in its catalogue's
`overview/0`, under `time` (`Catalog.overview/0`).

# `account_day`

```elixir
@type account_day() :: %{
  day: Date.t(),
  user_id: String.t(),
  seconds: float(),
  by: %{required({String.t(), String.t() | nil}) =&gt; float()}
}
```

One account on one UTC day: seconds in all and per `{area, detail}`.

# `account_days`

```elixir
@spec account_days(Date.t(), Date.t(), keyword()) :: [account_day()]
```

Every account with time on a UTC day in `from..to` (inclusive), one
`t:account_day/0` each. Options: `segment:` (`Gamend.Analytics.segments/0`).

# `report`

```elixir
@spec report(pos_integer(), Date.t(), keyword()) :: map()
```

The time spent over the last `days` UTC days ending on `today` (today
partial), for the admin Analytics Time tab:

  * `seconds`, `people` (accounts with any time), `account_days`,
    `per_day_avg` / `per_day_median` (seconds per account on a day it
    came), `per_person` (seconds per account over the window);
  * `series`: per day `%{day, people, seconds, avg, median}`;
  * `buckets`: account-days by how long, `%{label, count}`;
  * `areas`: `%{id, label, people, account_days, seconds, avg, share}`,
    `avg` per account-day that used the area, most time first;
  * `details`: the same per `{area, detail}` where there is a detail.

Options: `segment:`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
