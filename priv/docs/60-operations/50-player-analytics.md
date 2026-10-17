---
icon: hero-chart-bar
---

# Player analytics

`Gamend.Analytics` is the one place aggregate numbers come from: the public
stats page, the admin index, `/admin/analytics`, `/api/v1/stats` and the
`/api/v1/admin/analytics/*` endpoints all read it. Nothing to configure; the
numbers appear as soon as players log in.

## What is measured

| Family | Numbers | Source |
|---|---|---|
| Activity | DAU / WAU / MAU (distinct users seen today / last 7 / last 30 days), stickiness (DAU ÷ MAU), new users per UTC day | `user_activity_days`, `users.inserted_at` |
| Retention | D1 / D7 / D30 — of the users who registered on day *C*, the share seen again on **exactly** *C+1* / *C+7* / *C+30*; pooled over the last 60 days of cohorts that have reached the horizon | same |
| Payers | Distinct users with a completed purchase in the last 30 days, and that ÷ MAU | `purchases` |
| Snapshot | Live counters from every context — players, lobbies, parties, quests, signaling, matchmaking queue, tournaments — composed once, cached a minute | the contexts' `stats/0` |
| Economy flow | Currency granted / spent per UTC day per ledger `reason` — whatever labels your game passes, e.g. `match_reward`, `store_purchase` | `ledger_entries` |
| Counters | Game-defined per-day counters written with `Analytics.count/3`. Core writes `payments.*`; the rest are yours, e.g. `level.started`, `level.finished`, sliced by a dimension after a colon (`level.started.mode:ranked`) | `analytics_daily_counts` |
| Events | `Analytics.track/3`: counts the name and each dimension like `count/3` AND, for an account, keeps the row (who, when, every field). The rows answer what a sum cannot: how many distinct people did a thing, their return rates per feature, averages of a score. A visitor's event (no user id) is counted, never kept | `analytics_events` |

"Seen" is any authenticated contact: a login (session or JWT), a socket
heartbeat, an offline→online transition, and every signed-in web request
and LiveView mount (a reader back on their session cookie signs nothing in;
before 2026-10-14 those days were missed). Days are UTC, like every other
period on the server.

Every people number splits by **segment** (`Analytics.segments/0`,
`segment:` on the functions, `?segment=` on the API): `registered` (an
account with an email or a provider), `guest` (a device or browser only,
`User.anonymous?/1`) or `all`. The split is by what the account is now.

Retention is the strict "back on day N" definition, so the numbers line up
with what stores and ad networks report; it is not "active at any point in
the first week". A dash means no cohort has reached that horizon yet, rather than
0%.

## Where it lives

- `user_activity_days`: one row per user per UTC day seen, written once by
  `Analytics.record_activity/2` from the `last_seen_at` touches in
  `Gamend.Accounts`. Deduped through the cache, so a heartbeat costs a cache
  read, not a write. Grows by *active users × days*;
  `GAMEND_RETENTION_ACTIVITY_DAYS` prunes older rows (below 60 the cohort
  numbers go blank).
- `analytics_daily_counts`: one row per `(day, key)`, incremented in place.
  Bounded by *keys × days*. Keys are dotted strings the game owns; put a
  dimension after a colon (`level.started.lang:ja`) so `counts/3` can pull a
  family with `level.started.lang:*`.
- `client_sessions`: one row per run of the game on a device, written by
  [client log](/docs/client-logs) uploads. Bounded by *players ×
  sessions per day*; the log lines themselves are **not** stored here, they go
  out through `Logger` to whatever log store the host runs. Pruned by
  `GAMEND_CLIENT_LOGS_RETENTION_DAYS` (14), or
  `GAMEND_CLIENT_LOGS_RETENTION_FLAGGED_DAYS` (90) for sessions that logged an
  error.
- Everything else is read straight from the owning tables.

## The admin pages and the catalogue

`/admin/analytics` is tabs, every filter in the URL:

| Tab | Shows |
|---|---|
| Overview | DAU / WAU / MAU, stickiness, D1 / D7 / D30, payers; charts of active and new accounts and stickiness per day; the per-day table (each day's own WAU / MAU / stickiness) |
| Features | Every event, grouped by the catalogue: accounts today / 7 / 30 days, first-timers and their D1 / D7 / D30, events |
| Explore | One event, a group or all, over 7 / 30 / 90 days: filters on any dimension, events and accounts per day (and the counter, visitors included), averages and rates of its numbers, a breakdown by any dimension, the rows page by page |
| People | One account: kind, days seen (13 weeks), events by name and one by one, coin ledger |
| Counters | Every counter family, grouped, with a sparkline and its dimensions |
| Economy | Granted and spent per day per currency, by ledger reason |

A host says what its events MEAN with a catalogue,
`config :gamend_core, :analytics_catalog, MyGame.Analytics`, a module
implementing `Gamend.Analytics.Catalog`: `groups/0` (id, label, the name
prefixes a group files), `events/0` (name, group, label, `dims` and
`measures` with labels, `rates` like `{"score", "total", "Score"}`, `kind`
`:event` or `:counter`) and, optionally, `tabs/0` for its own pages, which
draw `GamendWeb.AdminLive.AnalyticsComponents.analytics_header/1`. Without
one, every name is filed under its first two segments and labelled with
itself. `Gamend.Analytics.Explore` is the query side, usable from a host's
own pages.

Reporting a counter from a plugin:

```elixir
Gamend.Analytics.count("level.finished")            # +1 today
Gamend.Analytics.count("shop.open", 1)
Gamend.Analytics.count("level.started.lang:ja", 3)
```

Never raises; a bad key is dropped. Call it from paths that already write
(a level end, a purchase), not from paths that otherwise only read.

## API

| Endpoint | Returns |
|---|---|
| `GET /api/v1/stats` (public, gated by `GAMEND_FEATURES_PUBLIC_STATS`) | The snapshot: players, activity, lobbies, parties, quests, signaling, matchmaking queue, tournaments |
| `GET /api/v1/admin/analytics?segment=all` | Summary: DAU / WAU / MAU, stickiness, new users, D1 / D7 / D30, payers |
| `GET /api/v1/admin/analytics/daily?days=30&segment=all` | Per-day rows, oldest first: `active`, `wau`, `mau`, `stickiness`, `new_users`, `d1`, `d7`, `d30` |
| `GET /api/v1/admin/analytics/snapshot` | The snapshot, regardless of the public gate |
| `GET /api/v1/admin/analytics/economy?days=7&currency=coins` | `totals` per `{currency, reason}` and per-day `flow` |
| `GET /api/v1/admin/analytics/counts?key=level.*&days=7` | Counter totals and per-day series by key or prefix |

Rates are `0.0–1.0` or `null`. Admin JWT required except for `/api/v1/stats`.

## What the data can and cannot answer

Already answerable from existing tables (no new plumbing):

| Question | From |
|---|---|
| Sign-ups, DAU, retention, stickiness | `user_activity_days`, `users` |
| Coin sources vs sinks per day, inflation | `ledger_entries.reason` (economy flow) |
| Quest completion → claim conversion and lag; daily-quest completion per day (`period_key` is the date) | `quest_progress.completed_at/claimed_at` |
| Tournament funnel registered → active → winner, no-show rate, round duration | `tournament_entries.state`, `tournament_matches.ready_at/resolved_at/expired_at` |
| Matchmaking wait time (`matched_at − queued_at`) — last 24 h only, tickets are pruned | `matchmaking_tickets` |
| Ready-check accept / dodge rate | `ready_checks` |
| Revenue per day, ARPPU, refund rate, provider split | `purchases` |
| Chat volume, share of DAU that chats; moderation load | `chat_messages`, `chat_reports`, `chat_mutes` |
| Notification read rate; reachable installs by platform | `notifications.read`, `push_tokens` |
| Item ownership, wallet distribution | `inventory_items`, `wallets` |

Answerable **only via counters** your game writes: anything about a match or a
level once it is over, since a lobby is usually deleted when the match ends and
nothing else records it (matches started / finished / abandoned per day, per
mode, solo vs group), and the funnel around any gate your game adds.

Not recorded by core; add a counter or a table if you need it: session length
and peak concurrency history; onboarding funnel steps; shop opens / SKU views /
checkout abandons; push delivery/open outcomes; per-user platform, country or
acquisition channel for segmenting retention.
