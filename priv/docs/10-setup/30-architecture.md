---
icon: hero-cube-transparent
---

# Architecture

High-level overview of how the platform is structured, from clients down to the database and external services.

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
  │                         GAMEND                              │
  │                                                             │
  │  ┌───────────────────── Web Layer ───────────────────────┐  │
  │  │  REST API (/api/v1) │ WS Channels + WebRTC │ Admin    │  │
  │  │  (Controllers +     │ (Lobby, User,        │ UI       │  │
  │  │   OpenApiSpex)      │  Signaling, …)       │ (Live)   │  │
  │  └─────────────────────┴──────────────────────┴──────────┘  │
  │                        │                      │             │
  │  ┌──────── Auth ──────────────────────────────────────────┐ │
  │  │  Guardian (JWT) │ Sessions │ Ueberauth │ Captcha (opt) │ │
  │  └──────────┬──────┴───────┬──┴───────────┴─┬─────────────┘ │
  │             │              │                │               │
  │  ┌───────── Business Layer (Contexts) ────────────────────┐ │
  │  │                                                        │ │
  │  │  Accounts │ Lobbies │ Parties │ Friends │ Groups       │ │
  │  │  Leaderboards │ Tournaments │ Matchmaking │ Ready      │ │
  │  │  Quests │ Chat │ Economy │ Inventory │ Payments        │ │
  │  │  KV │ Storage │ Signaling │ Push │ Jobs │ Hooks        │ │
  │  │                                                        │ │
  │  └──────────┬─────────────────────┬───────────────────────┘ │
  │             │                     │                         │
  │  ┌──────── Infrastructure ────────┴───────────────────────┐ │
  │  │  PubSub (real-time) │ Cache (Nebulex) │ Oban (cron)    │ │
  │  └──────────┬──────────┴───────────┬─────┴────────────────┘ │
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
  Signaling module ──────►  "signaling:{lobby_id}"       ──►  SignalingChannel (presence)
  Signaling module ──────►  "signaling:{lobby_id}:{uid}" ──►  SignalingChannel (one peer's
                                                              inbox: relayed offer/answer/ice)
```

Signaling has no room process and no room record: configuration is read from
the lobby's `webrtc_*` columns, membership is presence, and relay is PubSub. All
three are cluster-wide, so two peers whose sockets land on different nodes can
still signal each other.

## Entity relationships (simplified)

```text
  users ─────┬──── lobby_id ──────────► lobbies
             │                            ├── webrtc_* columns
             │                            │   (the WebRTC signaling room IS
             │                            │    the lobby; server-owned, not
             │                            │    castable, star host = host_id)
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
  gamend/                 # The runnable host app itself
  ├── lib/gamend_host/    # Router, supervision tree, boot config, branding
  ├── lib/gamend_web/     # Host-owned pages (docs, blog, presentation)
  ├── priv/docs/               # These guides, as markdown
  ├── apps/
  │   ├── gamend_core/    # Shared domain: contexts, schemas, migrations
  │   └── gamend_web/     # Shared web package: controllers, LiveViews,
  │                            #   channels, components, frontend source
  ├── modules/plugins/         # Hook plugins, as OTP apps (server scripting)
  ├── clients/                 # Godot SDK, JS SDK
  └── sdk/                     # Elixir SDK stubs for hooks
```

## The contexts

Business logic lives in context modules under `gamend_core`, each owning
one domain and callable from a plugin. Their functions, arguments and return
values are documented in the
[Elixir API reference](https://docs.gamend.org/api-reference.html):

| Domain | Module |
|---|---|
| Accounts, auth, presence | [`Gamend.Accounts`](https://docs.gamend.org/Gamend.Accounts.html) |
| Lobbies | [`Gamend.Lobbies`](https://docs.gamend.org/Gamend.Lobbies.html) |
| Parties | [`Gamend.Parties`](https://docs.gamend.org/Gamend.Parties.html) |
| Groups | [`Gamend.Groups`](https://docs.gamend.org/Gamend.Groups.html) |
| Friends and blacklist | [`Gamend.Friends`](https://docs.gamend.org/Gamend.Friends.html) |
| Chat | [`Gamend.Chat`](https://docs.gamend.org/Gamend.Chat.html) |
| Quests | [`Gamend.Quests`](https://docs.gamend.org/Gamend.Quests.html) |
| Leaderboards | [`Gamend.Leaderboards`](https://docs.gamend.org/Gamend.Leaderboards.html) |
| Tournaments | [`Gamend.Tournaments`](https://docs.gamend.org/Gamend.Tournaments.html) |
| Matchmaking | [`Gamend.Matchmaking`](https://docs.gamend.org/Gamend.Matchmaking.html) |
| Notifications | [`Gamend.Notifications`](https://docs.gamend.org/Gamend.Notifications.html) |
| Wallets and inventory | [`Gamend.Economy`](https://docs.gamend.org/Gamend.Economy.html) |
| Payments | [`Gamend.Payments`](https://docs.gamend.org/Gamend.Payments.html) |
| Key-value store | [`Gamend.KV`](https://docs.gamend.org/Gamend.KV.html) |
| Object storage | [`Gamend.Storage`](https://docs.gamend.org/Gamend.Storage.html) |
| WebRTC signaling rooms | [`Gamend.Signaling`](https://docs.gamend.org/Gamend.Signaling.html) |
| Ready checks | [`Gamend.ReadyChecks`](https://docs.gamend.org/Gamend.ReadyChecks.html) |
| Background and cron jobs | [`Gamend.Jobs`](https://docs.gamend.org/Gamend.Jobs.html), [`Gamend.Schedule`](https://docs.gamend.org/Gamend.Schedule.html) |
| Plugin hooks | [`Gamend.Hooks`](https://docs.gamend.org/Gamend.Hooks.html) |

## Key technologies

- **Framework:** Phoenix 1.8 + LiveView
- **Language:** Elixir 1.20 / Erlang OTP
- **HTTP server:** Bandit (native HTTPS, no reverse proxy needed)
- **Database:** SQLite3 (default) / PostgreSQL (optional)
- **Real-time:** Phoenix Channels + PubSub; WebRTC DataChannels (ex_webrtc) and peer-to-peer signaling
- **Auth:** Guardian (JWT), Ueberauth (OAuth), Sessions, optional Cloudflare Turnstile captcha
- **Cache:** Nebulex (L1 local, optional L2 Redis/partitioned)
- **Jobs and scheduling:** Oban (durable queues + cron)
- **API docs:** OpenApiSpex (Swagger UI)
- **CSS:** Tailwind CSS 4
- **Monitoring:** Telemetry + PromEx
