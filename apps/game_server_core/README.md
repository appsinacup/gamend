# GameServer Core

The domain layer of [Gamend](https://gamend.appsinacup.com) — an open-source
Elixir game server for real-time multiplayer games. This package holds the
contexts, schemas and migrations; `game_server_web` adds the REST API,
WebSocket channels, LiveView admin and the generated client SDKs.

You call these modules from a **plugin**: a small OTP application the server
loads at boot, implementing the `GameServer.Hooks` behaviour. That is the
supported way to add game-specific rules without forking anything.

## What it gives you

| Area | What you get |
|---|---|
| **Accounts** | Email/password, magic link, device (guest) and OAuth for Discord, Google, Apple, Facebook and Steam. JWT access/refresh plus browser sessions, per-user revocation, presence. |
| **Lobbies** | Create/join/leave with capacity, passwords, visibility and a server-owned lifecycle `state`. Membership lives on the user, so a player is in at most one. |
| **Matchmaking** | A ticket queue grouping players by exact parameters into hidden lobbies; parties queue as an indivisible unit, blocks are honoured while groups form, and a hook can replace the matcher outright. |
| **Ready checks** | "Everyone must answer before this proceeds", one row per participant, resolving to a pass or fail your game acts on. |
| **Social** | Friends and a blacklist in one table, groups with roles and join requests, parties, and chat across lobbies, groups and DMs with read cursors. |
| **Progression** | Quests covering achievements, dailies, seasonal events and chains; leaderboards with `set`/`best`/`incr`/`decr` operators and seasons; bracket tournaments with timed rounds. |
| **Economy** | Virtual-currency wallets and an inventory, each backed by an append-only, idempotent ledger, so a retried grant cannot pay out twice. |
| **Payments** | Stripe, Google Play, App Store and Steam, reconciled into one purchase ledger and entitlement model. |
| **Storage** | Per-user, per-lobby and global key-value entries, plus object storage on local disk or S3/R2. |
| **Delivery** | In-app notifications and push over FCM and APNs, routed per device token. |
| **Operations** | Rate limiting, IP bans, caching (Nebulex, optional Redis L2), background jobs (Oban), scheduling, and retention that bounds every table which would otherwise grow forever. |

Everything runs on **SQLite or PostgreSQL** — the same migrations target both.

## Installation

```elixir
def deps do
  [
    {:game_server_core, "~> 1.0.0"}
  ]
end
```

## Where to start

- **[Guides](https://gamend.appsinacup.com/docs/setup)** — deployment, OAuth
  provider setup, client SDKs and a walkthrough of each subsystem.
- **[HTTP API](https://gamend.appsinacup.com/api/docs)** — every endpoint,
  generated from the OpenAPI spec.
- **`GameServer.Hooks`** — the plugin behaviour. Every callback is optional;
  `before_*` may veto an operation, `after_*` observes one that already
  committed.

Each domain has one context module as its entry point, so `GameServer.Lobbies`,
`GameServer.Quests` and `GameServer.Economy` are the first three worth reading.
The schema modules beneath them (`GameServer.Lobbies.Lobby` and so on) carry the
field types and changesets.
