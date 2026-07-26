---
icon: hero-circle-stack
---

# Data Schema

The tables a game reads, writes or joins against, and what their columns mean.
Two companions to this page:

- [**Admin runtime**](/admin/runtime) - a live ER diagram of every table,
  generated from the running schema.
- [**Elixir API**](https://appsinacup.com/game_server/api-reference.html) - each
  schema module with its `t:t/0` type and changesets.

The field lists below are curated: they cover the columns you will actually
touch and the invariants that are not visible from a type.

## Conventions

These hold everywhere, so the tables below list only what is specific to them:

- **Ids** are UUIDv7 strings — time-ordered, so they sort chronologically.
- **Timestamps** are `utc_datetime` and always UTC. Every table has
  `inserted_at` and `updated_at` unless noted.
- **`metadata`** is a free-form JSON map you own. Core never interprets it.
- **Foreign keys** cascade on delete unless noted, so removing a user removes
  their rows.

## users

[`GameServer.Accounts.User`](https://appsinacup.com/game_server/GameServer.Accounts.User.html)

| Column | Type | Notes |
|---|---|---|
| `email` | string | Unique; null for provider-only accounts |
| `hashed_password` | string | bcrypt; null for OAuth-only accounts |
| `username` | string | Unique lowercase handle, generated at registration |
| `display_name` | string | Human-friendly, not unique |
| `profile_url` | string | Avatar URL |
| `discord_id` `google_id` `facebook_id` `steam_id` `apple_id` `device_id` | string | Linked identities, all nullable |
| `is_admin` | boolean | Grants `/admin` and the admin API |
| `is_activated` | boolean | `false` blocks login without deleting the account |
| `is_online` | boolean | Presence; cleared on disconnect |
| `last_seen_at` | utc_datetime | Stamped when presence drops |
| `token_version` | integer | Bump to revoke every JWT the user holds |
| `lobby_id` | FK lobbies | Current lobby, nullable. **Not** cleared on disconnect |
| `party_id` | FK parties | Current party, nullable |
| `confirmed_at` | utc_datetime | Email confirmation |
| `metadata` | map | Yours |

## lobbies

[`GameServer.Lobbies.Lobby`](https://appsinacup.com/game_server/GameServer.Lobbies.Lobby.html)

| Column | Type | Notes |
|---|---|---|
| `title` | string | Display title, unique |
| `host_id` | FK users | Null for hostless (matchmaking-owned) lobbies |
| `hostless` | boolean | Server owns it; no player may edit it |
| `max_users` | integer | Default 8 |
| `is_hidden` | boolean | Excluded from public listings |
| `is_locked` | boolean | Blocks joins; server code may pass `bypass_lock` |
| `password_hash` | string | bcrypt; optional join password |
| `state` | string | Lifecycle word. Core sets `created`; the game owns the vocabulary (enforced in `before_lobby_state_change`) |
| `state_changed_at` | utc_datetime | When `state` last changed |
| `slowdown` | integer | Chat slow-mode seconds, 0 = off |
| `metadata` | map | Searchable in lobby listings |

Membership lives on `users.lobby_id`, not a join table — a user is in at most
one lobby, and disconnecting does not clear it. `state` is server-owned: the
host may set it on a host-managed lobby via `POST /lobbies/state`, hostless
lobbies are server-only, and a plain lobby update can never write it. Core
validates only that the word is 1-64 bytes and enforces no ordering, so a game
that wants a closed vocabulary rejects the move in `before_lobby_state_change`.

## parties

| Column | Type | Notes |
|---|---|---|
| `leader_id` | FK users | Creator; invites are leader-only |
| `max_size` | integer | Default 4 |

Membership is `users.party_id`. Invites live in `party_invites`
(`party_id`, `sender_id`, `recipient_id`, `status`) — independent of
notifications, so deleting the notification does not cancel the invite.

## friendships

[`GameServer.Friends.Friendship`](https://appsinacup.com/game_server/GameServer.Friends.Friendship.html)

| Column | Type | Notes |
|---|---|---|
| `requester_id` | FK users | Who asked; **the blocked user** when status is `blocked` |
| `target_id` | FK users | Who was asked; **the blocker** when status is `blocked` |
| `status` | string | `pending` / `accepted` / `rejected` / `blocked` |

Unique on `(requester_id, target_id)`. One table carries both friendships and
the blacklist: a block is always stored in the canonical direction regardless
of who sent the original request, so at most one row exists per pair and a
block reliably supersedes an existing friendship. Blocks are read in both
directions and enforced in matchmaking, lobby joins, party and group invites,
chat and friend requests.

## groups

| Column | Type | Notes |
|---|---|---|
| `title` | string | Display name |
| `type` | string | `public` / `private` / `hidden`, default `public` |
| `max_members` | integer | Default 100 |
| `creator_id` | FK users | Owner |
| `slowdown` | integer | Chat slow-mode seconds |

Membership is `group_members`; `group_invites` and `group_join_requests` carry
the two directions of joining, each with a `status`.

## kv_entries

| Column | Type | Notes |
|---|---|---|
| `key` | string | Namespaced by the schema patterns a plugin registers |
| `user_id` | FK users | Set for user-scoped keys |
| `lobby_id` | FK lobbies | Set for lobby-scoped keys; deleted with the lobby |
| `value` | map | The stored JSON |

Global entries leave both ids null. Writes are server-authoritative where a
plugin declares a schema for the key.

## quests

One table drives achievements, dailies, seasonal events and quest lines. What
separates them is `reset` (how often progress restarts) and `category` (how you
group them for display) — an achievement is a quest that never resets. There is
no separate achievements table.

| Column | Type | Notes |
|---|---|---|
| `key` | string | Unique slug, e.g. `daily_win_3` |
| `title` `description` `icon_url` | string | Display |
| `reset` | string | `never` / `daily` / `weekly` / `monthly` / `interval` |
| `reset_interval_days` | integer | With `reset: "interval"`; 14 = biweekly |
| `category` | string | Free-form grouping, e.g. `achievement` |
| `objectives` | jsonb | List of `{event, target, params}` |
| `rewards` | jsonb | List of `{type, code, amount}` |
| `auto_claim` | boolean | Grant on completion instead of requiring a claim |
| `prerequisite_quest_key` | string | Chains; nullable |
| `starts_at` / `ends_at` | utc_datetime | Event window; nullable |
| `hidden` | boolean | Listed but obscured until completed |
| `sort_order` | integer | Display order |
| `active` | boolean | Soft disable |

## quest_progress

| Column | Type | Notes |
|---|---|---|
| `user_id` | FK users | |
| `quest_key` | string | FK to `quests.key` |
| `period_key` | string | Reset bucket: `static`, `2026-07-22`, `2026-W30` |
| `objective_progress` | jsonb | Objective index to count |
| `status` | string | `active` / `completed` / `claimed` |
| `completed_at` | utc_datetime | Null until every objective is met |
| `claimed_at` | utc_datetime | Null until rewards are claimed |
| `rewards_granted_at` | utc_datetime | Null until every reward applied |

Unique on `(user_id, quest_key, period_key)`. A new period is simply a new row
on the next reported event — nothing fires at midnight, and period boundaries
are UTC.

## leaderboards and leaderboard_records

[`GameServer.Leaderboards.Leaderboard`](https://appsinacup.com/game_server/GameServer.Leaderboards.Leaderboard.html)

| leaderboards | Type | Notes |
|---|---|---|
| `slug` | string | Unique identifier |
| `sort_order` | enum | `asc` / `desc`, default `desc` |
| `operator` | enum | `set` / `best` / `incr` / `decr`, default `best` |
| `starts_at` / `ends_at` | utc_datetime | Optional window; null `ends_at` = open |

| leaderboard_records | Type | Notes |
|---|---|---|
| `leaderboard_id` | FK leaderboards | |
| `user_id` | FK users | Nullable — a record may belong to a label instead |
| `label` | string | Team or arbitrary entrant name |
| `score` | integer | Combined per the board's `operator` |
| `rank` | integer | Materialised on write |

## chat_messages and chat_read_cursors

| chat_messages | Type | Notes |
|---|---|---|
| `sender_id` | FK users | |
| `content` | string | 1-4096 chars |
| `chat_type` | string | `lobby` / `group` / `friend` |
| `chat_ref_id` | uuid | Lobby id, group id, or the other user's id |

| chat_read_cursors | Type | Notes |
|---|---|---|
| `user_id` | FK users | |
| `chat_type` / `chat_ref_id` | | Which conversation |
| `last_read_message_id` | FK chat_messages | Drives unread counts |

Access is checked per type: lobby and group messages require membership, direct
messages require an accepted friendship and no block either way.

## notifications

| Column | Type | Notes |
|---|---|---|
| `sender_id` / `recipient_id` | FK users | |
| `title` `content` | string | |
| `read` | boolean | |
| `metadata.type` | string | Routes client handling, e.g. `quest_completed` |

`quest_completed` carries `{ quest_key, category, quest_title }`. Plugins
declare their own types via `notification_types/0`; undeclared types are
rejected at the push site.

## wallets and inventory

| wallets | Type | Notes |
|---|---|---|
| `user_id` | FK users | Unique with `currency` |
| `currency` | string | e.g. `coins` |
| `balance` | integer | Never written directly; changed through the ledger |

| inventory_items | Type | Notes |
|---|---|---|
| `user_id` | FK users | Unique with `item` |
| `item` | string | Item code |
| `quantity` | integer | |

Every balance change appends to `ledger_entries` (and `inventory_ledger` for
items) with an `idempotency_key`, so a retried grant cannot pay out twice. The
ledger is the audit trail; the balance is a cache of it.

## Everything else

| Table | Holds | Guide |
|---|---|---|
| `users_tokens` | Session, magic-link and email-change tokens, pruned on their own expiry | Authentication |
| `oauth_sessions` | In-flight OAuth handshakes, pruned daily | Authentication |
| `ip_bans` | Address bans, with optional expiry | — |
| `matchmaking_tickets` | Queue state, one per user or party | Matchmaking |
| `ready_checks`, `ready_check_participants` | "Everyone must answer" boards on a lobby or party, one row per participant | Matchmaking |
| `tournaments`, `tournament_entries`, `tournament_matches`, `tournament_brackets` | Bracket state per occurrence | Tournaments |
| `lobby_snapshots`, `lobby_events`, `lobby_snapshot_blobs` | Opt-in per-run recording for debugging | — |
| `purchases`, `entitlements`, `store_products`, `provider_products`, `provider_events`, `reconciliation_cursors` | Store catalogue, receipts and provider webhooks | Payments |
| `push_tokens` | Device tokens for push, pruned when stale | Push notifications |

Anything that grows without bound has a retention window; see the
`RETENTION_*` variables in the Deployment guide.
