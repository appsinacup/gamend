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
| Economy flow | Currency granted / spent per UTC day per ledger `reason` (`treasure`, `unlock_item`, `refill_lives`, …) | `ledger_entries` |
| Counters | Game-defined per-day counters written with `Analytics.count/3` — `level.started`, `level.finished`, `level.failed`, `level.abandoned`, `lives.blocked_start`, each also sliced `…lang:<code>`, `level.started.mode:<mode>`, `level.started.{solo,coop,tournament}` | `analytics_daily_counts` |

"Seen" is any authenticated contact: a login (session or JWT), a socket
heartbeat, or an offline→online transition, the same events that move
`users.last_seen_at`. Days are UTC, like every other period on the server.

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
  [client log](/docs/godot-sdk) uploads. Bounded by *players ×
  sessions per day*; the log lines themselves are **not** stored here, they go
  out through `Logger` to whatever log store the host runs. Pruned by
  `client_logs.retention_days` (14), or `retention_flagged_days` (90) for
  sessions that logged an error.
- Everything else is read straight from the owning tables.

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
| `GET /api/v1/stats` (public, gated by `PUBLIC_STATS`) | The snapshot: players, activity, lobbies, parties, quests, signaling, matchmaking queue, tournaments |
| `GET /api/v1/admin/analytics` | Summary: DAU / WAU / MAU, stickiness, new users, D1 / D7 / D30, payers |
| `GET /api/v1/admin/analytics/daily?days=30` | Per-day rows, oldest first: `active`, `new_users`, `d1`, `d7`, `d30` |
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
| Cosmetic ownership, upgrade levels, cargo holdings, wallet distribution | `inventory_items`, `wallets` |

Answerable now **only via counters** the game writes (a lobby is deleted at
level end, so nothing else records it): levels started / finished / failed /
abandoned per day, per language, per mode; solo vs co-op vs tournament
starts; starts blocked by empty hearts (pair with `refill_lives` spends for
the paywall funnel).

Still not recorded anywhere; add a counter or a table if you need it:
session length and peak concurrency history; onboarding funnel steps
(language chosen → first level → tutorial done); shop opens / SKU views /
checkout abandons; per-guess accuracy over time (word stats are a per-user
blob); push delivery/open outcomes; per-user platform, country or acquisition
channel for segmenting retention.
