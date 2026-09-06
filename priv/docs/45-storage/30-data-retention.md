---
icon: hero-clock
---

# Data Retention

A supervised sweeper (`Gamend.Retention`) prunes unbounded tables on a schedule: a first pass five minutes after boot, then every six hours. Each window is one setting, a `GAMEND_RETENTION_*` env var, in days unless the name says otherwise, and `0` means keep forever. Deletes run in batches of 500, are idempotent so several instances sweeping at once is harmless, are failure-isolated per class, and each class emits `[:gamend, :retention, :pruned]` telemetry with its count.

## Pruning windows

| Variable | Default | What is pruned |
|---|---|---|
| `GAMEND_RETENTION_CHAT_MESSAGES_DAYS` | `0` | Chat messages older than N days. |
| `GAMEND_RETENTION_NOTIFICATIONS_DAYS` | `0` | Notifications older than N days. |
| `GAMEND_RETENTION_PAYMENT_EVENTS_DAYS` | `0` | Payment provider webhook events. Purchases and entitlements are never pruned. |
| `GAMEND_RETENTION_LOBBY_SNAPSHOTS_DAYS` | `30` | Lobby snapshots, events and content blobs. Defaults *on*: snapshots hold user metadata and KV, and this window is what bounds that exposure. |
| `GAMEND_RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` | `90` | Longer window for snapshots of runs flagged anomalous. |
| `GAMEND_RETENTION_MATCHMAKING_TICKETS_HOURS` | `24` | Matchmaking tickets in any status — note: hours. |
| `GAMEND_RETENTION_INVITES_DAYS` | `30` | Resolved group/party invites and join requests, N days after resolution. Pending rows are never touched. |
| `GAMEND_RETENTION_PUSH_TOKENS_DAYS` | `270` | Push tokens untouched (registered, used, or disabled) for N days. |
| `GAMEND_RETENTION_TOURNAMENTS_DAYS` | `0` | Finished and cancelled tournaments (entries, matches and brackets cascade). |
| `GAMEND_RETENTION_LEDGER_DAYS` | `0` | Wallet and inventory ledger entries — the audit trail behind every balance, so opt-in only. |
| `GAMEND_RETENTION_ACTIVITY_DAYS` | `0` | Per-user daily activity rows (the DAU / D1-D7-D30 source). Below 60, the admin analytics cohorts go blank. |
| `GAMEND_RETENTION_ANONYMOUS_USERS_DAYS` | `90` | Device-only accounts inactive for N days. |
| `GAMEND_RETENTION_INACTIVE_USERS_DAYS` | `0` | Accounts with a real identity, after N days of inactivity — see the warning flow below. |

Client log *sessions* are pruned on the client-logs module's own settings (`retention_days` 14, `retention_flagged_days` 90, keyed off `last_seen_at`). That prunes the searchable index over sessions, not the log lines, which live in the host's log store on its own retention. And some cleanups have no variable at all: expired IP bans, OAuth sessions older than a day, user tokens past their context's validity, and stored avatars whose owner no longer exists are always removed. The full variable list, with types and defaults, is in [Settings](/docs/settings).

## Abandoned lobbies and parties

`GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES` (default `15`, `0` disables) does two things with one window:

- **A disconnected player's seat is released** after 15 minutes of silence while their lobby lives on. Disconnecting does not clear `users.lobby_id` — a returning player rejoins their game — but `join_lobby` and `create_lobby` refuse with `already_in_lobby`, so without this a player who never returns would be locked out of playing anything until their old teammates stopped. The release goes through `Lobbies.leave_lobby/1`, so host migration, lobby-scoped KV cleanup and broadcasts all run.
- **A lobby nobody has been seen in** for 15 minutes — and that has not itself been touched — is deleted. "Seen" is `last_seen_at`, never the `is_online` flag alone: connected sockets refresh it continuously, while a hard server stop freezes the flag at `true`. A game that ends a match knows it ended and can delete its lobby itself; silence is the only signal core can read on its own, so it is the only one it acts on.

`GAMEND_RETENTION_ABANDONED_PARTY_MINUTES` (default `15`) is the party equivalent: a member offline past the window is removed via `Parties.leave_party/1` (a departing leader disbands the party, since there is no host migration for parties), and a party whose every member has gone quiet is disbanded. Seat release and lobby reaping deliberately share one window: releasing seats sooner would make a merely-paused lobby look empty and let the reaper delete a game under players who are only disconnected.

## Row deletes vs. context deletes

Most classes are plain "rows older than the cutoff". The ones that carry live game state are not: lobby reaping runs through `Lobbies.delete_lobby/1`, seat release through `leave_lobby/1`, party cleanup through `leave_party/1` / `Parties.disband/1`, and account deletion through `Accounts.delete_user/1`, so KV cascades, hooks, host migration and broadcasts all still fire for a swept row exactly as they would for a voluntary one.

The orphaned-avatar sweep is the one class that prunes *object storage* rather than a table: stored avatars whose owner segment no longer matches a user are deleted, but only after a 60-minute grace period (so an object mid-write is never mistaken for an orphan), walking the `avatars/` prefix a page at a time with a per-sweep page ceiling.

## Inactivity account deletion

With `GAMEND_RETENTION_INACTIVE_USERS_DAYS` set (it defaults to `0`, keep forever; `730` matches what Google and Microsoft use), identified accounts are deleted after that many days of inactivity, and `GAMEND_RETENTION_INACTIVE_USERS_WARN_DAYS` (default `30`) emails a warning that many days before the cutoff. The warning is an Oban job (`Gamend.Accounts.InactivityNotifier`) that stamps `retention_warned_at` in the user's metadata only after a successful send: an un-warned account is one the sweep refuses to delete, so a mail outage postpones a deletion rather than performing a silent one, and only a warning issued after the user's last activity counts. Accounts with no email address cannot be warned and are deleted at the cutoff; admins, and anyone holding a purchase or entitlement, are never swept at any age. Deletion runs through `Accounts.delete_user/1`, so party disband, group handover, storage cleanup and the `after_user_deleted` hook all fire.

## Server scripting

```elixir
Gamend.Retention.run_now()   # sweep immediately; returns per-class deleted counts
Gamend.Retention.status()    # last run time, duration, per-class results
Gamend.Retention.prune_all() # one pass, outside the GenServer (tests, scripts)
```

## Operations

The **Admin → Retention** page (`/admin/retention`) shows every configured window (variable name, current value, and whether it is still the default) alongside the last sweep: when it ran, how long it took, and a table of rows pruned per class (classes that pruned nothing are hidden). A **Run now** button runs a manual sweep. The same is scriptable over the admin API (`GET /api/v1/admin/retention` for status, `POST /api/v1/admin/retention/run` to sweep), so a deploy pipeline can prune on demand.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - the Admin – Retention endpoints, generated from the spec.
- **Elixir API:** [`Gamend.Retention`](https://docs.gamend.org/Gamend.Retention.html) - windows, sweep mechanics and the functions a script calls.
