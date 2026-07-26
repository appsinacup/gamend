---
icon: hero-cube-transparent
---

# Architecture

High-level overview of how the platform is structured — from clients down to the database and external services.

## System overview

```text
  ┌─────────────────────────────────────────────────────────────┐
  │                        CLIENTS                              │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
  │  │  Godot SDK   │  │   JS SDK     │  │ Web Browser  │       │
  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
  └─────────┼─────────────────┼─────────────────┼───────────────┘
            │ REST + WS       │ REST + WS       │ HTTP
            ▼                 ▼                 ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                     GAME SERVER                             │
  │                                                             │
  │  ┌───────────────────── Web Layer ───────────────────────┐  │
  │  │  REST API (/api/v1)  │  WebSocket Channels  │  Admin  │  │
  │  │  (Controllers +      │  (Lobby, User,       │  UI     │  │
  │  │   OpenApiSpex)       │   other channels)    │  (Live) │  │
  │  └──────────┬───────────┴──────────┬───────────┴────┬────┘  │
  │             │                      │                │       │
  │  ┌──────── Auth ──────────────────────────────────────────┐ │
  │  │  Guardian (JWT)  │  Sessions  │  Ueberauth (OAuth)     │ │
  │  └──────────┬───────┴──────┬─────┴──────────┬─────────────┘ │
  │             │              │                │               │
  │  ┌───────── Business Layer (Contexts) ────────────────────┐ │
  │  │                                                        │ │
  │  │  Accounts  │  Lobbies       │  Parties  │  Friends     │ │
  │  │  Groups    │  Leaderboards  │  Notifications │ Push    │ │
  │  │  Quests    │ Chat  │  Economy  │  Inventory        │ │
  │  │  KV Storage │ Hooks (server scripting)                 │ │
  │  │                                                        │ │
  │  └──────────┬─────────────────────┬───────────────────────┘ │
  │             │                     │                         │
  │  ┌──────── Infrastructure ────────┴───────────────────────┐ │
  │  │  PubSub (real-time)  │  Cache (Nebulex)  │  Scheduler  │ │
  │  └──────────┬───────────┴──────────┬────────┴─────────────┘ │
  └─────────────┼──────────────────────┼────────────────────────┘
                │                      │
  ┌─────────────┼──────────────────────┼───────────────────────┐
  │             ▼     EXTERNAL         ▼                       │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
  │  │   Database   │  │    Redis     │  │  OAuth       │      │
  │  │ SQLite / PG  │  │  (optional)  │  │  Providers   │      │
  │  └──────────────┘  └──────────────┘  └──────────────┘      │
  │  ┌──────────────┐  ┌──────────────────────────────┐        │
  │  │  Email SMTP  │  │  Push: FCM / APNs (optional) │        │
  │  └──────────────┘  └──────────────────────────────┘        │
  └────────────────────────────────────────────────────────────┘
```

## Request flow

```text
  Client ──► Endpoint ──► Router ──► Pipeline (auth) ──► Controller/LiveView
                                                              │
                                                              ▼
                                                        Context module
                                                       (business logic)
                                                              │
                                                              ▼
                                                        Ecto / Repo
                                                              │
                                                              ▼
                                                          Database
```

## Real-time (PubSub topics)

```text
  Publishers                  Topics                          Subscribers
  ──────────                  ──────                          ───────────
  Lobbies module   ──────►  "lobby:{id}"                 ──►  LobbyChannel
                            (incl. state_changed)
  Lobbies module   ──────►  "lobbies"                    ──►  LobbiesChannel, LiveViews
  Parties module   ──────►  "party:{id}"                 ──►  PartyChannel
  Parties module   ──────►  "parties"                    ──►  LiveViews
  Parties/Groups   ──────►  "user:{id}"                  ──►  UserChannel (invite events)
  Accounts module  ──────►  "user:{id}"                  ──►  UserChannel (updated, friend_updated)
  Friends module   ──────►  "friends:user:{id}"          ──►  LiveViews
  Groups module    ──────►  "group:{id}"                 ──►  GroupChannel, LiveViews
  Groups module    ──────►  "groups"                     ──►  GroupsChannel, LiveViews
  Notifications    ──────►  "notifications:user:{id}"    ──►  UserChannel
  Chat module      ──────►  "chat:lobby:{id}"            ──►  LobbyChannel
  Chat module      ──────►  "chat:group:{id}"            ──►  GroupChannel
  Chat module      ──────►  "chat:party:{id}"            ──►  PartyChannel
  Chat module      ──────►  "chat:friend:{lo}:{hi}"      ──►  UserChannel
                            + "user:{id}" (friend DMs)
  Quests module    ──────►  "user:{id}"                  ──►  UserChannel, LiveViews
                            (quest_progress/completed/claimed)
  Quests module    ──────►  "quests"                     ──►  Admin LiveViews
  KV module        ──────►  "kv:{scope}:{key}"           ──►  UserChannel (kv:subscribe)
  Tournaments      ──────►  "tournaments:user:{id}"      ──►  UserChannel
  Payments module  ──────►  "user:{id}"                  ──►  LiveViews (purchases/entitlements)
```

## Entity relationships (simplified)

```text
  users ─────┬──── lobby_id ──────────► lobbies
             │                            │
             ├──── party_id ──────────► parties
             │                              └── party_invites table
             │                                  (sender_id → recipient_id,
             │                                   party_id, status)
             │
             ├──── friendships ◄─────► friendships
             │         status: pending | accepted | rejected | blocked
             │         "blocked" is the blacklist: enforced in
             │         matchmaking, lobby joins, invites and chat
             │
             ├──── group_members ─────► groups
             │                              ├── group_join_requests
             │                              └── group_invites table
             │                                  (sender_id → recipient_id,
             │                                   group_id, status)
             │
             ├──── leaderboard_records ► leaderboards
             │
             ├──── notifications (send / receive)
             │       Invites are stored in dedicated tables
             │       (group_invites, party_invites) and are
             │       independent of notifications.
             │
             ├──── push_tokens (registered devices)
             │       Committed notifications also fan out to the
             │       recipient's live device tokens (FCM / APNs).
             │
             ├──── chat_messages (sender_id ─► messages)
             │         chat_type: lobby | group | friend
             │         chat_ref_id ─► lobby/group/user
             │
             ├──── chat_read_cursors (unread tracking)
             │
             ├──── quest_progress ──────► quests
             │       (per period_key; an achievement is
             │        just a quest with reset "never")
             │
             ├──── tournament_entries ──► tournaments
             │       (leader_id, seed,        ├── tournament_brackets
             │        wins, state)            └── tournament_matches
             │                                    (a/b/winner entry ids,
             │                                     round, slot, deadline)
             │
             ├──── kv_entries (scoped: global, per-user,
             │       per-lobby, per-user-per-lobby)
             │
             ├──── purchases / entitlements ──► products
             │       (payment_provider_events as audit trail)
             │
             └──── users_tokens, oauth_sessions
```

## Repository layout

These projects live in one repository, but the runtime split is intentional: core and web are reusable packages, while host is the runnable shell you own.

```text
  game_server/                 # The runnable host app itself
  ├── lib/game_server_host/    # Router, supervision tree, boot config, branding
  ├── lib/game_server_web/     # Host-owned pages (docs, blog, presentation)
  ├── priv/docs/               # These guides, as markdown
  ├── apps/
  │   ├── game_server_core/    # Shared domain: contexts, schemas, migrations
  │   └── game_server_web/     # Shared web package: controllers, LiveViews,
  │                            #   channels, components, frontend source
  ├── modules/                 # Runtime hook scripts (server scripting)
  ├── clients/                 # Godot SDK, JS SDK
  └── sdk/                     # Elixir SDK stubs for hooks
```

## The contexts

Business logic lives in context modules under `game_server_core`, each owning
one domain and callable from a plugin. Their functions, arguments and return
values are documented in the
[Elixir API reference](https://appsinacup.com/game_server/api-reference.html):

| Domain | Module |
|---|---|
| Accounts, auth, presence | [`GameServer.Accounts`](https://appsinacup.com/game_server/GameServer.Accounts.html) |
| Lobbies | [`GameServer.Lobbies`](https://appsinacup.com/game_server/GameServer.Lobbies.html) |
| Parties | [`GameServer.Parties`](https://appsinacup.com/game_server/GameServer.Parties.html) |
| Groups | [`GameServer.Groups`](https://appsinacup.com/game_server/GameServer.Groups.html) |
| Friends and blacklist | [`GameServer.Friends`](https://appsinacup.com/game_server/GameServer.Friends.html) |
| Chat | [`GameServer.Chat`](https://appsinacup.com/game_server/GameServer.Chat.html) |
| Quests | [`GameServer.Quests`](https://appsinacup.com/game_server/GameServer.Quests.html) |
| Leaderboards | [`GameServer.Leaderboards`](https://appsinacup.com/game_server/GameServer.Leaderboards.html) |
| Tournaments | [`GameServer.Tournaments`](https://appsinacup.com/game_server/GameServer.Tournaments.html) |
| Matchmaking | [`GameServer.Matchmaking`](https://appsinacup.com/game_server/GameServer.Matchmaking.html) |
| Notifications | [`GameServer.Notifications`](https://appsinacup.com/game_server/GameServer.Notifications.html) |
| Wallets and inventory | [`GameServer.Economy`](https://appsinacup.com/game_server/GameServer.Economy.html) |
| Payments | [`GameServer.Payments`](https://appsinacup.com/game_server/GameServer.Payments.html) |
| Key-value store | [`GameServer.KV`](https://appsinacup.com/game_server/GameServer.KV.html) |
| Plugin hooks | [`GameServer.Hooks`](https://appsinacup.com/game_server/GameServer.Hooks.html) |

## Key technologies

- **Framework:** Phoenix 1.8 + LiveView
- **Language:** Elixir 1.20 / Erlang OTP
- **HTTP server:** Bandit (native HTTPS, no reverse proxy needed)
- **Database:** SQLite3 (default) / PostgreSQL (optional)
- **Real-time:** Phoenix Channels + PubSub; WebRTC DataChannels (ex_webrtc)
- **Auth:** Guardian (JWT), Ueberauth (OAuth), Sessions
- **Cache:** Nebulex (L1 local, optional L2 Redis/partitioned)
- **Scheduling:** Quantum (cron-like)
- **API docs:** OpenApiSpex (Swagger UI)
- **CSS:** Tailwind CSS 4
- **Monitoring:** Telemetry + PromEx
