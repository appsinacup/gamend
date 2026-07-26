defmodule GameServerWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Game Server API.
  """

  alias GameServerWeb.{Endpoint, Router}
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server, Tag}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "Game Server API",
        version: api_version(),
        description: """
        API for the Gamend Game Server. Provides HTTP REST API, real-time WebSocket channels, and WebRTC DataChannels for low-latency game data. Features authentication, users, lobbies, groups, parties, friends, chat, notifications, quests, leaderboards, tournaments, matchmaking, payments, server scripting, and admin portal.

        ## **1. Authentication**

        This API uses JWT (JSON Web Tokens) with access and refresh tokens:

        ### **1.1 Getting Tokens**
        - **Email/Password**: POST to `/api/v1/login` with email and password
        - **Device (SDK)**: POST to `/api/v1/login` with a `device_id` string (creates/returns a device user)
        - **Discord OAuth**: Use `/api/v1/auth/discord` flow
        - **Google OAuth**: Use `/api/v1/auth/google` flow
        - **Facebook OAuth**: Use `/api/v1/auth/facebook` flow
        - **Apple Sign In**: Use `/auth/apple` browser flow or apple sdk flow
        - **Steam (OpenID)**: Use `/api/v1/auth/steam` flow

        Both methods return:
        - `access_token` - Short-lived (15 min), use for API requests
        - `refresh_token` - Long-lived (30 days), use to get new access tokens

        ### **1.2 Using Tokens**
        Include the access token in the Authorization header:
        ```
        Authorization: Bearer <access_token>
        ```

        ### **1.3 Refreshing Tokens**
        When your access token expires, use POST `/api/v1/refresh` with your refresh token to get a new access token.

        ## **2. Users**
        Users endpoints cover the user lifecycle and profile features. Key highlights:

        - **Registration and login** (email/password, device token for SDKs, and OAuth providers)
        - **Profile metadata** (JSON blob per user) and editable profile fields
        - **Account lifecycle**: password reset, email confirmation, and account deletion
        - **Sessions & tokens**: both browser sessions and JWT-based API tokens are supported

        ## **3. Friends**
        The Friends domain offers lightweight social features:

        - **Friend requests** (send / accept / reject / block flows)
        - **Friend listing & pagination**, with basic privacy controls
        - **Domain helpers** to manage and query friend relationships from API or UI contexts

        ## **4. Lobbies**
        Lobbies provide matchmaking / room management primitives. Highlights:

        - **Create / list / update / delete** lobbies with rich metadata (mode, region, tags)
        - **Host-managed or hostless** modes (hostless allowed internally, not creatable via public API)
        - **Membership management**: join, leave, kick users, and automatic host transfer
        - **Controls & protection**: max users, hidden/locked states, and optional password protection
        - **Hidden lobbies** are excluded from public listings; public listing endpoints are paginated

        ## **5. Notifications**
        Persistent user-to-user notifications that survive across sessions:

        - **Send notifications** to accepted friends with a title, optional content, and optional metadata
        - **List own notifications** with pagination (ordered oldest-first)
        - **Delete notifications** by ID (single or batch)
        - **Real-time delivery** via the user WebSocket channel (`"notification"` events)
        - **Offline delivery**: undeleted notifications are replayed on WebSocket reconnect
        - **Push delivery**: notifications also fan out to the recipient's registered mobile devices (see Push notifications)

        ## **5b. Push notifications**
        Mobile/web push delivery to registered devices (FCM for Android/Web, APNs-direct for iOS):

        - **Register device tokens** via `POST /me/push_tokens` (`token`, `platform`, optional `provider`/`device_id`); re-registering a `device_id` rotates its token in place
        - **List/remove own devices** via `GET /me/push_tokens` and `DELETE /me/push_tokens/:id`
        - **Server-authoritative sending** — no public send endpoint; pushes originate from server hooks (`GameServer.Push.send_to_user/2`) or the admin API
        - **Per-token routing**: each token's `provider` ("fcm" | "apns") selects the delivery backend; unconfigured backends log instead of sending (dev-friendly)
        - **Reliability**: delivery rides the durable job queue with retries; dead tokens reported by the provider are disabled automatically

        ## **6. Groups**
        Groups provide persistent community management for players:

        - **Three group types**: `public` (anyone joins directly), `private` (users request to join, admins approve), `hidden` (invite-only, never listed)
        - **Membership roles**: `admin` and `member`, with promote/demote capabilities
        - **Join requests**: for private groups, users submit requests that admins approve or reject
        - **Invitations**: admins can invite users directly (blocked users are rejected)
        - **CRUD operations**: create, update, delete groups with metadata support
        - **Group chat**: integrated via the Chat API with `chat_type: "group"`

        ## **7. Parties**
        Ephemeral groups of users for short-lived sessions (e.g., matchmaking squads):

        - **Invite-only joining**: the party leader sends invites by user ID to friends or shared-group members
        - **Invite flow**: `POST /parties/invite` → recipient accepts via `POST /parties/invite/accept` or declines via `POST /parties/invite/decline`; leader can cancel via `POST /parties/invite/cancel`
        - **Invite visibility**: leader can list sent invites (`GET /parties/invitations/sent`); recipient can list received invites (`GET /parties/invitations`)
        - **Connection requirement**: invites can only be sent to users who are friends or share at least one group with the leader
        - **One party at a time**: a user can only be in one party; accepting an invite while already in a party is rejected
        - **Leader management**: the creator is the leader; leadership can be transferred
        - **Lobby integration**: parties can create or join lobbies as a group
        - **Party chat**: integrated via the Chat API with `chat_type: "party"`
        - **Real-time events** via the party WebSocket channel

        ## **8. Chat**
        Real-time messaging across multiple conversation types:

        - **Chat types**: `lobby` (within a lobby), `group` (within a group), `party` (within a party), `friend` (DMs between friends)
        - **Send messages** with content, optional metadata, and automatic access validation
        - **List messages** with pagination (newest first)
        - **Read tracking**: mark messages as read and get unread counts per conversation
        - **Real-time delivery** via PubSub and WebSocket channels
        - **Moderation hooks**: `before_chat_message` pipeline hook for filtering/blocking

        ## **9. Leaderboards**
        Server-managed ranked scoreboards:

        - **Multiple leaderboards**: create named leaderboards with configurable sort order
        - **Score submission**: submit scores with optional metadata
        - **Rankings**: retrieve paginated rankings with user details
        - **Reset support**: leaderboards can be reset periodically

        ## **10. Key-Value Storage**
        Per-user persistent key-value storage for game state, preferences, and settings:

        - **Get/set/delete** key-value pairs scoped to the authenticated user
        - **List keys** with optional prefix filtering
        - **Metadata support**: values can include arbitrary JSON metadata

        ## **11. Quests / Progression**
        One event-driven progression engine covering achievements, daily/weekly quests, time-boxed event quests, and chains:

        - **Kinds**: `achievement` (permanent one-shot — the replacement for the old achievements system), `daily`/`weekly` (reset per UTC period), `event` (starts_at/ends_at window), `chain` (requires a prerequisite quest)
        - **Objectives**: each quest lists objectives `{event, target, params}`; server-side `report_event` advances every matching active quest — there is **no public endpoint to advance progress** (server-authoritative)
        - **Rewards**: currencies (Economy) and items (Inventory), paid **exactly once** per period via idempotent grants; `auto_claim` quests pay on completion, others via `POST /me/quests/:key/claim`
        - **My quests**: `GET /me/quests` returns active quests, per-period progress, and a claimable flag; hidden quests appear once completed
        - **Catalog**: `GET /quests` and per-user completions `GET /quests/user/:user_id` (gated by `LIST_QUESTS_ENABLED`)
        - **Admin management**: definitions CRUD plus per-user grant/reset/force-claim under `/api/v1/admin/quests`

        ## **12. Tournaments**
        Single-elimination bracket tournaments, server-structured and game-judged:

        - **Registration window → seeded draw → timed rounds → champions**; recurring tournaments (cron) create one occurrence per cycle sharing a slug; a nil starts_at keeps registration open until an admin draws manually
        - **Join/leave** as an entry leader (`POST`/`DELETE /tournaments/:id/join`); team composition is game policy
        - **Browse**: list/filter tournaments, standings, full bracket view, and the caller's current match (`GET /tournaments/:id/my_match`)
        - **Match verdicts are server-side** (game hooks) — no public resolve endpoint; clients get `tournament_match_ready` / `tournament_match_resolved` / `tournament_updated` / `tournament_finished` on the user channel
        - **Admin management** over HTTP: create/update/delete, cancel, draw now, finish, and force match verdicts under `/api/v1/admin/tournaments`

        ## **13. Matchmaking**
        Ticket-based queueing that turns waiting players into hidden, locked lobbies:

        - **Join over HTTP** (`POST /matchmaking/tickets` with a `match_params` string map); only tickets with identical params match together — encode mode/map/skill band as parameter values
        - **A match forms** when a group reaches `max_players`, or has at least `min_players` and the oldest ticket outwaited the timeout; the server creates a hidden lobby, seats everyone and locks it
        - **The result is a push, not a poll**: matched players receive `match_found` (`lobby_id`, `match_params`) on their user channel; disconnecting cancels your tickets
        - **Inspect**: `GET /matchmaking/tickets/me` for your ticket, `GET /matchmaking/stats` for queue depths
        - **Admin management** over HTTP: list/filter tickets, force-cancel, and stats under `/api/v1/admin/matchmaking`

        ## **14. Ready checks**
        One primitive for "everyone must answer before this proceeds", with one client-facing surface:

        - **A player holds at most one check per lane** — the match lane (lobby ready-up or matchmaking accept) and the party lane (the party's standing board) — so answering needs no id: `GET /me/ready_check` returns `{"lobby": …, "party": …}` (each null when none) and `POST /me/ready_check` with `{"ready": true|false, "scope": "lobby"|"party"}` answers one (scope defaults to `lobby`)
        - **Two kinds.** `ready` (lobby/party board) is a toggle — a "no" just leaves the check open, and it lists every participant. `accept` (match confirmation) is final — one decline fails it for everyone — and returns counts plus your own state, so a pending match does not reveal who you were paired with
        - **Hosts open one** with `POST /lobbies/ready_check` (host-managed lobbies only; hostless matchmaking lobbies belong to the server), **party leaders** with `POST /parties/ready_check`; either call is a **reset** — it quietly replaces an already-open board with a fresh one over the current members, so the same endpoint serves "ready check!", "force ready" (with `timeout_ms`) and "start over". Call it off with `DELETE /lobbies/ready_check` / `DELETE /parties/ready_check`. The opener is pre-marked ready — clicking the button is their answer
        - **Failure does nothing on its own**: a declined or timed-out check kicks nobody, starts nothing, and moves no lobby state. It reports who did not answer, and the game (or the host, with the kick they already have) decides
        - **Live**: `ready_check_started` / `ready_check_updated` / `ready_check_passed` / `ready_check_failed` on the lobby channel, the party channel for a party board, or the user channel for an accept check
        - **Admin management** over HTTP: list/filter checks, force-cancel, and 24h outcome stats under `/api/v1/admin/ready_checks`

        ## **15. Real-time: WebSocket Channels**
        The server provides real-time communication via Phoenix WebSocket channels. Connect to the WebSocket endpoint and join topic-based channels for live updates.

        ### **15.1 Connection**
        Connect to `wss://your-server.com/socket` with your JWT token as a parameter:
        ```
        const socket = new Socket("wss://your-server.com/socket", { params: { token: "<access_token>" } })
        socket.connect()
        ```

        ### **15.2 Available Channels**
        - **User channel** (`user:<user_id>`): notifications, friend events, quest progress/completions/claims, party/group invites, tournament events, KV subscriptions
        - **Lobby channel** (`lobby:<lobby_id>`): lobby member joins/leaves, lobby updates, lobby chat
        - **Lobbies channel** (`lobbies`): global lobby list changes (created, updated, deleted)
        - **Group channel** (`group:<group_id>`): group member changes, group updates, group chat
        - **Groups channel** (`groups`): global group list changes
        - **Party channel** (`party:<party_id>`): party member changes, party updates, party chat

        ### **15.3 JS SDK Helper**
        The `GameRealtime` class (included in this SDK) wraps Phoenix.Socket with convenient channel helpers:
        ```javascript
        import { GameRealtime } from '@ughuuu/game_server'
        const realtime = new GameRealtime('https://your-server.com', accessToken)
        const userChannel = realtime.joinUserChannel(userId)
        userChannel.on('notification', payload => console.log(payload))
        ```
        Requires the `phoenix` npm package as a peer dependency: `npm install phoenix`

        ## **16. Real-time: WebRTC DataChannels**
        For low-latency game data, the server supports WebRTC DataChannels alongside WebSocket. The server acts as a WebRTC peer (not P2P between clients).

        ### **16.1 How It Works**
        1. Client connects via WebSocket and joins the **User channel**
        2. Client sends an SDP offer over the channel (`webrtc:offer` event)
        3. Server responds with an SDP answer (`webrtc:answer` event)
        4. ICE candidates are exchanged (`webrtc:ice` events)
        5. Once connected, named DataChannels carry game data at low latency

        ### **16.2 Default DataChannels**
        - **`events`** (reliable, ordered): important game events (player actions, state changes)
        - **`state`** (unreliable, unordered): high-frequency position/state sync

        ### **16.3 JS SDK Helper**
        The `GameWebRTC` class (included in this SDK, browser-only) handles signaling automatically:
        ```javascript
        import { GameRealtime, GameWebRTC } from '@ughuuu/game_server'
        const realtime = new GameRealtime('https://your-server.com', token)
        const userChannel = realtime.joinUserChannel(userId)
        const webrtc = new GameWebRTC(userChannel, {
          onData: (label, data) => console.log(label, data)
        })
        await webrtc.connect()
        webrtc.send('events', JSON.stringify({ type: 'move', x: 10, y: 20 }))
        ```
        """
      },
      paths: filter_api_paths(Paths.from_router(Router)),
      tags: [
        # --- Public API ---
        %Tag{
          name: "Authentication",
          description: "Login, registration, OAuth, and token management"
        },
        %Tag{name: "Users", description: "User profiles, metadata, and account management"},
        %Tag{name: "Friends", description: "Friend requests, blocking, and friend lists"},
        %Tag{name: "Lobbies", description: "Matchmaking rooms — create, join, leave, and manage"},
        %Tag{
          name: "Groups",
          description: "Persistent community groups with roles and permissions"
        },
        %Tag{
          name: "Parties",
          description: "Ephemeral party groups — invite-only, leader-managed"
        },
        %Tag{
          name: "Chat",
          description: "Real-time messaging across lobbies, groups, parties, and friends"
        },
        %Tag{name: "Notifications", description: "Persistent user notifications"},
        %Tag{name: "Push", description: "Device push-token registration"},
        %Tag{name: "Leaderboards", description: "Ranked scoreboards and score submission"},
        %Tag{name: "Tournaments", description: "Bracket tournaments — browse, join, standings"},
        %Tag{
          name: "Matchmaking",
          description: "Ticket queue — join, cancel, your ticket, queue stats"
        },
        %Tag{
          name: "Ready checks",
          description: "Ready up / accept — read and answer the caller's open check"
        },
        %Tag{
          name: "Quests",
          description: "Quests/progression — objectives, periods, claims, rewards"
        },
        %Tag{
          name: "Payments",
          description: "Store catalog, checkout, receipts, purchases, and entitlements"
        },
        %Tag{name: "KV", description: "Per-user key-value storage"},
        %Tag{
          name: "Economy",
          description: "Currency wallets and item inventory (read-only for clients)"
        },
        %Tag{name: "Hooks", description: "Server scripting hooks"},
        %Tag{name: "Health", description: "Server health check"},
        # --- Admin API ---
        %Tag{name: "Admin – Users", description: "Admin user management"},
        %Tag{name: "Admin – Sessions", description: "Admin session management"},
        %Tag{name: "Admin – Lobbies", description: "Admin lobby management"},
        %Tag{name: "Admin – Groups", description: "Admin group management"},
        %Tag{name: "Admin – Chat", description: "Admin chat management"},
        %Tag{name: "Admin – Quests", description: "Admin quest management"},
        %Tag{name: "Admin – Notifications", description: "Admin notification management"},
        %Tag{name: "Admin – Push", description: "Admin push-token management and sending"},
        %Tag{name: "Admin – Leaderboards", description: "Admin leaderboard management"},
        %Tag{name: "Admin – Tournaments", description: "Admin tournament management"},
        %Tag{name: "Admin – Matchmaking", description: "Admin matchmaking queue management"},
        %Tag{
          name: "Admin – Ready checks",
          description: "Admin ready-check inspection and force-cancel"
        },
        %Tag{name: "Admin – KV", description: "Admin key-value storage management"},
        %Tag{
          name: "Admin – Economy",
          description: "Admin currency & inventory grant/spend and browse"
        },
        %Tag{name: "Admin – Storage", description: "Admin object storage management"}
      ],
      components: %Components{
        securitySchemes: %{
          "authorization" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description:
              "JWT access token - obtain from /api/v1/login, /api/v1/auth/discord/callback, /api/v1/auth/google/callback, /api/v1/auth/facebook/callback, or /auth/apple"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp api_version do
    # The declared setting wins: the image supplies it at runtime, while the
    # compiled vsn keeps mix.exs's default so the version cannot bust the
    # Docker layer cache. Falls back to the vsn, then the Mix project version.
    case GameServer.Settings.get(GameServer.ContentSettings, :app_version) ||
           Application.spec(:game_server, :vsn) do
      nil -> Mix.Project.config()[:version] || "1.0.0"
      vsn -> to_string(vsn)
    end
  end

  # Filter out non-API routes (browser routes) from the OpenAPI spec
  defp filter_api_paths(paths) do
    Map.filter(paths, fn {path, _path_item} ->
      # Only include paths that start with /api/
      String.starts_with?(path, "/api/")
    end)
  end
end
