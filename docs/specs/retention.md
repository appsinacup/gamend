# Retention for every unbounded table

Design spec. Extends `GameServer.Retention` from the seven classes it prunes
today to every table that grows without bound, on one configurable pattern.

Goal: no table in a long-running deployment grows forever unless an operator
chose that, and every window is a documented `RETENTION_*` env var.

## Where we are

`Retention` is a supervised GenServer that sweeps every 6h (5 min after boot)
and already prunes: chat messages, notifications, payment provider events,
OAuth sessions, expired IP bans, lobby snapshots (+ events + blobs), quest
period rows, and push tokens. Oban prunes its own `oban_jobs` (7d, via
`Oban.Plugins.Pruner`), and matchmaking sweeps offline tickets in its worker.

Each entry follows the same shape — an env var read in
`config/host_runtime.exs`, `0`/unset meaning "keep forever", and a
`prune_older_than/2`-style helper. That pattern is the one this spec extends;
nothing about it changes.

## The gaps

Audited every table. These grow unbounded with **no** retention at all:

| Table | Why it grows | Proposed default |
| --- | --- | --- |
| `lobbies` | Core never deletes an abandoned lobby — only party disband, a failed matchmaking seat, or an admin do. Games write their own reapers (polyglot's is 362 lines). **15 min** after everyone goes quiet |
| `users_tokens` | Rows are deleted on logout/password change only. An expired session or magic-link token is dead weight that nothing removes. | **prune when expired** (see below) |
| `group_invites`, `party_invites`, `group_join_requests` | Resolved rows (`accepted`/`declined`/`rejected`/`cancelled`) are never deleted — one row per social interaction, forever. | **30 d** after resolution |
| `matchmaking_tickets` | The worker prunes tickets whose owner went offline, but a ticket whose owner stays connected and never matches has no upper bound. | **24 h** |
| `tournaments` + entries/matches/brackets | Finished tournaments and their bracket rows accumulate per occurrence; recurring tournaments create one per cycle. | **0 (keep)**, opt-in |
| `ledger_entries`, `inventory_ledger` | Append-only by design — one row per currency/item mutation, forever. | **0 (keep)** — financial audit trail; opt-in only |

Deliberately **not** given retention: `users`, `groups`,
`friendships`, `wallets`, `inventory_items`, `kv_entries`,
`leaderboard_records`, `chat_read_cursors`, `quests`, `purchases`,
`entitlements`, `store_products`, `provider_products`,
`reconciliation_cursors`. These are entity or balance state, not history —
they are bounded by their owners and deleting rows would destroy player data,
not reclaim garbage. (Cascade on user deletion already covers the per-user
ones.)

**Amendment (July 2026): `parties` moved off that list.** It was grouped with
entity state, but a party is not bounded by its owner the way a wallet is: a
party disbands only when its **leader** leaves, and disconnecting never clears
`users.party_id`, so a group that simply closes the game leaves a row that lives
forever — still holding every member (a user may be in only one party, so it
blocks their next one), still listed, still receiving invites. That is the
abandoned-lobby problem with a different column, so it gets the same rule and
the same silence test:

| Table | Why it grows | Proposed default |
| --- | --- | --- |
| `parties` | Disbands only on leader-leave; an abandoned party is never removed | **15 min** after every member goes quiet |

Reaping goes through `Parties.disband_party/1` per row, exactly as lobbies go
through `reap_lobby/1` — members' `party_id` cleared, pending invites cancelled,
caches invalidated, `party_disbanded` broadcast, `after_party_disband` fired. A
bulk delete would leave every member pointing at a party that no longer exists.
The default is the lobby's 15 minutes, because the two settings answer the same
question and a host should not have to learn two numbers; a game that wants
parties to outlive a session raises it, and `0` keeps them forever. Full
reasoning in [disconnect-grace.md](disconnect-grace.md), which is where the
per-user side of the same problem lives.

## Lobbies — the one that needs real logic

Everything else is "delete rows older than N". Lobbies are not, and getting
this wrong deletes live games. One rule:

> Delete a lobby when it has not been touched for
> `GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES` **and** no member is online or was online
> inside that window.

Note this is not "no members": `set_user_offline/1` clears `is_online` but
never `users.lobby_id`, so players who close the game stay members forever and
a zero-member rule would almost never fire. Everyone having gone quiet is what
abandonment looks like; a lobby with no members at all is the trivial case.

**Rejected: reaping on a terminal state.** An earlier draft gave states a
`terminal: true` / `prune_after_minutes` declaration and reaped `ended` lobbies
on their own shorter clock. Dropped: a game that ends a match knows it ended
and can call `delete_lobby/1` itself, so the rule only ever made reaping
*sooner* — the presence condition above applied to it too, so it could never
delete under a connected player anyway. Core assigns no meaning to any state
but `created`; deciding that `ended` means "delete this" was core inventing
semantics it does not own. `Lobbies.States` is now a vocabulary and nothing
more.

Deleting a lobby already cascades its KV and snapshots via `delete_lobby/1`;
the reaper reuses it rather than issuing raw deletes, so hooks and broadcasts
still fire.

## users_tokens — expiry, not age

Token rows carry a context (`session` 14d, `login` 15min, `change:*` 7d) whose
validity windows are already encoded in
`GameServer.Accounts.UserToken`. Pruning by a single age would either kill live
sessions or keep dead ones, so the sweep deletes **rows past their own
context's validity** — the same predicate the verify queries use, inverted.
No new env var; correctness, not policy.

## Configuration

New vars, all following the existing convention (read in
`config/host_runtime.exs`, `0` disables, documented in `.env.example`):

```
GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES=15      # lobbies everyone has gone quiet in
GAMEND_RETENTION_INVITES_DAYS=30                 # resolved invites/join requests
GAMEND_RETENTION_MATCHMAKING_TICKETS_HOURS=24    # never-matched tickets
GAMEND_RETENTION_TOURNAMENTS_DAYS=0              # finished tournaments (opt-in)
GAMEND_RETENTION_LEDGER_DAYS=0                   # wallet + inventory ledgers (opt-in)
```

Defaults live in `GameServer.Retention` itself, not only in
`config/host_runtime.exs` - that file's retention block sits inside the
prod-only branch, so a default written only there is "keep forever" in dev and
in any host that never sets the vars. The lobby window (15 min) and invites default to a real window
rather than "keep forever", because unbounded growth there is a bug, not a policy choice; ledgers and
tournaments default to keep because deleting them loses an audit trail.

## Batching and safety

The sweep runs on a live database, so each class deletes in **bounded
batches** (`@batch 500`) in a loop until a pass deletes nothing, rather than
one unbounded `DELETE`. On SQLite a large delete holds the write lock long
enough to stall gameplay writes; on Postgres it bloats a single transaction.
Batching also makes the run interruptible — a restart mid-sweep just resumes
next cycle.

Every class stays **idempotent and independent**: one class raising must not
abort the rest, so each is wrapped and logged, and the result map reports per
class as it does today.

## Observability

- `prune_all/0` keeps returning `%{class => count}`; the log line stays.
- Emit `[:game_server, :retention, :pruned]` telemetry per class so the counts
  reach Prometheus/Grafana like other metrics.
- **Admin**: a Retention card on `/admin` (last run, per-class counts) and a
  "Run now" action on the System page, with API parity. Operators currently
  have no way to see whether retention is working.

## Deferred / rejected

- **Per-table cron schedules: rejected.** One 6h sweep with per-class windows
  is enough; separate schedules multiply configuration for no gain.
- **Soft deletes / archive tables: rejected.** Retention exists to bound
  storage; moving rows sideways does not.
- **Pruning `leaderboard_records`: rejected.** Bounded by users × leaderboards,
  and a missing record is a lost player achievement, not garbage.
- **A plugin-declared retention class: defer.** A general "prune my table" API
  needs its own design.

## Definition of done (CONTRIBUTING)

- [x] Every gap above pruned, batched, and independently failure-isolated.
- [x] Lobby reaper deletes only lobbies everyone has gone quiet in, and goes
      through `delete_lobby/1` so cascades and hooks run.
- [x] `users_tokens` pruned by per-context validity, with a test per context.
- [x] New `RETENTION_*` vars in `config/host_runtime.exs` + `.env.example`,
      `0` disabling each.
- [x] Telemetry event per class; admin card + "Run now" + API parity + render test.
- [x] Docs page updated (Deployment/Operations), CHANGELOG, i18n.
- [x] Tests both adapters: each class prunes what it should and **nothing else**;
      a lobby with an online member survives; batching loops past one batch.
- [x] Polyglot's `lobby_cleanup.ex` reduced to what core cannot express, with
      its tests updated to match.
- [x] `mix format`, `mix credo --strict`, full `mix test` green.
