This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

## Repository architecture (core/web/root host)

This repo keeps `game_server_core` and `game_server_web` reusable under `apps/`, while the runnable host app now lives at the repository root.

- `apps/game_server_core`: domain code, contexts, schema, migrations, shared business logic.
- `apps/game_server_web`: reusable web/UI library (controllers, LiveViews, components, templates) and static assets under `apps/game_server_web/priv/static`.
- repository root: runnable host that starts the supervision tree and is the intended extension point for forks (routing, boot-time config, branding, root assets/static/theme/data).

### Running the app

- Dev entrypoint is the root host app: `mix dev.start` starts the repository-root `game_server_host` project.
- The Phoenix endpoint module is still `GameServerWeb.Endpoint` for compatibility (static paths, existing modules, UI library), but it is started by the host OTP application.

### Routing ownership / extension point

Routing is host-controlled without making `game_server_web` depend on `game_server_host` at compile time:

- Host router: `GameServerHost.Router` in `lib/game_server_host/router.ex`.
- Endpoint dispatch: `GameServerWeb.Endpoint` uses a small dispatch plug that reads `Application.get_env(:game_server_web, :router, GameServerWeb.Router)` and calls that module.
  - This avoids warnings like “`GameServerHost.Router.call/2 is undefined`” when compiling `game_server_web` in isolation.
- Host boot-time config: `GameServerHost.Application` sets `Application.put_env(:game_server_web, :router, GameServerHost.Router, persistent: true)` before starting the endpoint.

Fork guidance:

- Add/remove routes by editing `lib/game_server_host/router.ex`.
- If you *remove* upstream routes but the upstream UI still uses route helpers (`~p"..."`) pointing at `GameServerWeb.Router`, you can end up generating links for routes that the host no longer serves. If you want strict route removal, forks should adjust the UI accordingly (or provide replacement routes that match the UI’s expectations).### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      # NOTE: in this repo (umbrella split), web UI code lives under apps/game_server_web
      @source "../../apps/game_server_web/lib";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


<!-- phoenix-gen-auth-start -->
## Authentication

This application uses both session-based authentication (for browser flows) and JWT authentication (for API flows).

### Browser Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs and `live_session` scopes:
  - A plug `:fetch_current_scope_for_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - A `live_session :current_user` scope - for routes that need the current user but don't require authentication, similar to `:fetch_current_scope_for_user`
  - A `live_session :require_authenticated_user` scope - for routes that require authentication, similar to the plug with the same name
  - In both cases, a `@current_scope` is assigned to the Plug connection and LiveView socket
  - A plug `redirect_if_user_is_authenticated` that redirects to a default path in case the user is authenticated - useful for a registration page that should only be shown to unauthenticated users
- **Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**
- Always pass the assign `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- To derive/access `current_user` in templates, **always use the `@current_scope.user`**, never use **`@current_user`** in templates or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_user` can only be defined __once__ in the router, so all routes for the `live_session :current_user`  must be grouped in a single block
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug and `live_session` as described below**

### Routes that require authentication

LiveViews that require login should **always be placed inside the __existing__ `live_session :require_authenticated_user` block**:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: [{GameServerWeb.UserAuth, :require_authenticated}] do
        # phx.gen.auth generated routes
        live "/users/settings", UserLive.Settings, :edit
        live "/users/settings/confirm_email/:token", UserLive.Settings, :confirm_email
        # our own routes that require logged in user
        live "/", MyLiveThatRequiresAuth, :index
      end
    end

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

LiveViews that can work with or without authentication, **always use the __existing__ `:current_user` scope**, ie:

    scope "/", MyAppWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: [{GameServerWeb.UserAuth, :mount_current_scope}] do
        # our own routes that work with or without authentication
        live "/", PublicLive
      end
    end

Controllers automatically have the `current_scope` available if they use the `:browser` pipeline.

### API Authentication (JWT)

API routes use JWT tokens via Guardian for stateless authentication:

- API login endpoint (`POST /api/v1/login`) returns an access token (15 minutes) and a refresh token (30 days); `POST /api/v1/refresh` exchanges a valid refresh token for a new access token
- OAuth API endpoints also return JWT tokens
- Protected API routes use the `:api_auth` pipeline which:
  - Verifies JWT tokens from `Authorization: Bearer <token>` header
  - Loads the user and assigns `current_scope` to the connection
  - Returns 401 errors for invalid/missing tokens
- Verification loads the user from the database and compares the token's `"tv"` claim against `users.token_version` — bumping the version (password change, email change, `Accounts.revoke_all_tokens/1`) revokes all previously issued access and refresh tokens
- **Always** use the `:api_auth` pipeline for API routes that require authentication:

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/me", MeController, :show
      end

- In API controllers, access the authenticated user via `conn.assigns.current_scope.user` (Guardian pipeline sets this)
- Guardian implementation is in `apps/game_server_web/lib/game_server_web/auth/guardian.ex`
- Guardian pipeline is in `apps/game_server_web/lib/game_server_web/auth/pipeline.ex`

### User hooks

- User updates (both `update_user` and `update_user_display_name`) run through the `before_user_update(user, attrs)` hook — return `{:ok, attrs}` to allow (optionally modified) or `{:error, reason}` to block. After update, `after_user_updated(user)` fires asynchronously.

### Lobbies

- Lobbies are stored in the `lobbies` table with fields: `id`, `name`, `title`, `host_id`, `hostless`, `max_users`, `is_hidden`, `is_locked`, `password_hash`, `metadata`, `inserted_at`, `updated_at`.
- Membership is now stored on the `users` table via a nullable `lobby_id` field: a user can be in at most one lobby at a time.
- Hidden lobbies are never returned from public list APIs. Hostless lobbies are allowed as a server-managed concept.
- API endpoints live under `/api/v1/lobbies` and require authentication for creating (host becomes owner), joining, leaving, updating, and kicking users. Listing lobbies is public but excludes hidden lobbies.

### Groups

- Groups have three types: `"public"` (anyone can join directly), `"private"` (users request to join, admins approve), `"hidden"` (invite-only, never shown in public listings).
- Group context: `GameServer.Groups` (invites live in `GameServer.Groups.Invites`, join requests in `GameServer.Groups.JoinRequests`; the public API is re-exported from `GameServer.Groups`) — key functions: `list_groups/2`, `create_group/2`, `join_group/2` (public), `request_join/2` (private), `invite_to_group/3`, `leave_group/2`, `kick_member/3`, `promote_member/3`, `demote_member/3`, `approve_request/3`, `reject_request/3`.
- Group membership is stored in the `group_members` table with a `role` field (`"admin"` or `"member"`). The group creator becomes admin automatically.
- Join requests are stored in the `group_join_requests` table with `status`: `"pending"`, `"approved"`, `"rejected"`.
- **Group invites** are stored in the dedicated `group_invites` table with fields: `id`, `group_id`, `sender_id`, `recipient_id`, `status` (`"pending"`, `"accepted"`, `"declined"`, `"cancelled"`), `inserted_at`, `updated_at`. An informational notification is also sent, but the invite record is independent — deleting notifications does not affect pending invites.
- Inviting a blocked user (or a user who blocked you) returns `{:error, :blocked}`.
- Group creation runs through the `before_group_create(user, attrs)` hook — return `{:ok, attrs}` to allow or `{:error, reason}` to block. After creation, `after_group_create(group)` fires asynchronously. Group joining runs through the `before_group_join(user, group, opts)` hook. Group updates run through `before_group_update(group, attrs)` — return `{:ok, attrs}` to allow (optionally modified) or `{:error, reason}` to block. After update, `after_group_updated(group)` fires asynchronously.
- Group after-hooks (all fire-and-forget via `GameServer.Async.run`): `after_group_join(user_id, group)` fires after any successful join (public, invite accept, request approval). `after_group_leave(user_id, group_id)` fires after a user leaves. `after_group_kick(admin_id, target_id, group_id)` fires after a kick. `after_group_deleted(group)` fires after a group is deleted (including auto-delete when last member leaves).
- API endpoints live under `/api/v1/groups`. Admin API under `/api/v1/admin/groups`.

### Parties

- Parties are ephemeral groups of users (2-10 members by default). They exist only while members are online and are not persisted long-term.
- Party context: `GameServer.Parties` — key functions: `create_party/1`, `invite_to_party/2`, `cancel_party_invite/2`, `accept_party_invite/2`, `decline_party_invite/2`, `list_party_invitations/1`, `leave_party/2`, `kick_member/3`, `promote_leader/3`, `disband_party/2`.
- A user can only be in **one party at a time**. Creating a new party automatically leaves any existing party.
- Users join parties via invite: the party leader sends an invite by user_id (only to friends or users in a shared group); the recipient then accepts or declines.
- **Invite mechanism**: Invites are stored in the dedicated `party_invites` table with fields: `id`, `party_id`, `sender_id`, `recipient_id`, `status` (`"pending"`, `"accepted"`, `"declined"`, `"cancelled"`), `inserted_at`, `updated_at`. An informational notification is also sent, but the invite record is independent — deleting notifications does not affect pending invites. `invite_to_party/2` (leader only, target must be friend or shared group member), `accept_party_invite/2` (joins the party and marks invite as accepted), `decline_party_invite/2` (marks invite as declined), `cancel_party_invite/2` (leader deletes pending invite). `list_party_invitations/1` returns pending PartyInvite records.
- Joining is exclusively invite-based.
- Parties can create/join lobbies as a group: `create_lobby_with_party/2`, `join_lobby_with_party/2`. These check that no party member is already in another lobby.
- Party hooks: `before_party_create(user, attrs)` — return `{:ok, attrs}` to allow or `{:error, reason}` to block. `after_party_create(party)` fires asynchronously. `before_party_update(party, attrs)` — return `{:ok, attrs}` to allow or `{:error, reason}` to block. `after_party_updated(party)` fires asynchronously.
- Party after-hooks (all fire-and-forget via `GameServer.Async.run`): `after_party_join(user, party)` fires after invite accept. `after_party_leave(user, party_id)` fires after a user leaves. `after_party_kick(target, leader, party)` fires after a kick. `after_party_disband(party)` fires after party is disbanded.
- API endpoints live under `/api/v1/parties`.

### Friends & Blocking

- Friend context: `GameServer.Friends` — key functions: `send_request/2`, `accept_request/2`, `decline_request/2`, `remove_friend/2`, `block_user/2`, `unblock_user/2`, `blocked?/2`, `friends?/2`.
- `blocked?/2` is a public function that checks if either user has blocked the other (bidirectional). It is used by Groups and Chat to prevent inviting/messaging blocked users.
- `friends?/2` checks whether two users have an accepted friendship.
- Friend requests between blocked users are automatically rejected.
- API endpoints: `/api/v1/friends`, `/api/v1/friends/block`.

### Chat

- Chat context: `GameServer.Chat` — key functions: `send_message/2`, `list_messages/3`, `list_friend_messages/3`, `mark_read/4`, `count_unread/3`, `count_unread_friend/2`, `get_message/1`, `delete_messages/2`.
- Chat types: `"lobby"` (messages within a lobby), `"group"` (messages within a group), `"friend"` (DMs between friends).
- Messages stored in `chat_messages` table with `sender_id`, `content`, `metadata`, `chat_type`, `chat_ref_id`.
- Read tracking stored in `chat_read_cursors` table with `user_id`, `chat_type`, `chat_ref_id`, `last_read_message_id`.
- Access validation: lobby chat requires lobby membership, group chat requires group membership, friend chat requires accepted friendship and no blocking.
- Hooks: `before_chat_message(user, attrs)` pipeline hook for filtering/moderation — return `{:ok, attrs}` to allow, `{:error, reason}` to block. `after_chat_message(message)` fires asynchronously.
- Caching: uses Nebulex version-based caching for `list_messages` (60s TTL).
- API endpoints: `GET /api/v1/chat/messages`, `POST /api/v1/chat/messages`, `POST /api/v1/chat/read`, `GET /api/v1/chat/unread`.

### Quests / Progression

- Quest context: `GameServer.Quests` — key functions: `create_quest/1`, `update_quest/2`, `delete_quest/1`, `get_quest/1`, `get_quest_by_key/1`, `list_quests/1`, `report_event/4`, `claim/3`, `list_user_quests/2`, `list_user_completions/2`, `claimable_count/1`, `admin_complete/2`, `admin_reset/2`, `admin_claim/2`.
- Three orthogonal dimensions, so any combination works: `reset` (`never`/`daily`/`weekly`/`monthly`/`interval` + `reset_interval_days`) drives `period_key` bucketing — a new period means a fresh `quest_progress` row, nothing fires at midnight; `starts_at`/`ends_at` make it an event; `prerequisite_quest_key` makes it a chain (hidden and frozen until unlocked). `category` is a free-form UI label with no engine behavior — achievements are `reset: "never", category: "achievement"`.
- Definitions live in the `quests` table (`key` unique, `reset`, `reset_interval_days`, `category`, `objectives` jsonb list of `{event, target, params}`, `rewards` jsonb list of `{type, code, amount}`, `auto_claim`, `hidden`, `active`); per-user state in `quest_progress` (`user_id`, `quest_key`, `period_key`, `objective_progress` map of objective index → count, `status` active/completed/claimed, unique on `(user_id, quest_key, period_key)`).
- Progress is server-authoritative: there is **no public endpoint to advance a quest**. Core wires common events (`login`, `chat_message`, `score_submitted`, `lobby_joined`, `match_won`); games call `Quests.report_event(user_id, event, amount, meta)` from hooks for custom events. Objective `params` must all match the event meta.
- Rewards pay **exactly once**: claiming is an atomic `completed → claimed` transition, grants go through Economy/Inventory with per-entry idempotency keys (`"quest:<progress_id>:<index>"`), and `recover_pending_rewards/1` heals crashed grants. `auto_claim` quests pay on completion.
- Hooks: `before_quest_claim(user_id, quest, progress)` (veto-only pipeline, skipped for auto-claim), `after_quest_completed(progress)`, `after_quest_claimed(progress)` — all async via `GameServer.Async.run`. On completion a `quest_completed` notification is created (quests categorised "achievement" get "Achievement unlocked" wording).
- Realtime user-channel events: `quest_progress` (user topic only), `quest_completed`, `quest_claimed`.
- Definitions are cached (`GameServer.Cache`, version-bumped); completed/claimed periods are remembered in a done-marker cache so post-completion events skip the DB entirely.
- API endpoints: `GET /api/v1/me/quests` (auth), `POST /api/v1/me/quests/:key/claim` (auth), `GET /api/v1/quests` and `GET /api/v1/quests/user/:user_id` (public catalog/completions, gated by `LIST_QUESTS_ENABLED`). Admin API under `/api/v1/admin/quests` (CRUD, `GET /progress`, POST grant/reset/claim, `GET /:key/funnel`). Public LiveView at `/quests`; admin page at `/admin/quests`.

### Push notifications

- Push context: `GameServer.Push` — token registry (`register_token/2` upsert, `list_tokens/2`, `delete_token/2`, soft `disable_token/1`) + server-authoritative delivery (`send_to_user/3`, `send_to_users/3`; no public send endpoint).
- Delivery routes **per token** off `push_tokens.provider` ("fcm" | "apns") through Pigeon dispatchers; unconfigured providers fall back to the zero-config `Log` provider. One Oban job per token on the `push` queue (`GAMEND_PUSH_QUEUE_CONCURRENCY`); large fan-outs expand via `FanoutWorker`.
- Hooks: `before_push_send/2` (per-recipient veto/rewrite pipeline), `after_push_sent/3` (per-token outcome). `Notifications` bridges committed notifications to push for offline users via the cached `user_has_live_tokens?/1`.
- API: `POST/GET /api/v1/me/push_tokens`, `DELETE /api/v1/me/push_tokens/:id`; admin under `/api/v1/admin/push/*`; admin page at `/admin/push`. Stale tokens prune via `GAMEND_RETENTION_PUSH_TOKENS_DAYS` (default 270).

### Notifications

- Notification context: `GameServer.Notifications` — key functions: `admin_create_notification/3`, `create_chat_notification/3`, `send_notification/2`, `delete_notification_by/3`, `delete_notifications/2`.
- Schema: `id`, `sender_id`, `recipient_id`, `title`, `content`, `metadata` (map), `read` (boolean), timestamps. Upserts on `(sender_id, recipient_id, title)`.
- Friend notifications are created fire-and-forget at the event source in `GameServer.Friends` (via `GameServer.Async.run`), like all other domains — there is no PubSub-subscribing notifier process.
- All notifications carry a `metadata.type` string tag for client-side routing/filtering. The complete list of notification types:

  **Friends:**
  - `friend_request` — new incoming friend request
  - `friend_accepted` — your friend request was accepted
  - `friend_rejected` — your friend request was rejected

  **Groups:**
  - `group_invite` — invited to join a group
  - `group_invite_accepted` — your group invite was accepted
  - `group_invite_declined` — your group invite was declined
  - `group_join_request` — someone requested to join your group (sent to admins)
  - `group_join_request_approved` — your group join request was approved
  - `group_join_request_rejected` — your group join request was rejected
  - `group_kicked` — you were removed from a group
  - `group_promoted` — you were promoted to admin
  - `group_demoted` — you were demoted to member

  **Parties:**
  - `party_invite` — invited to join a party
  - `party_invite_accepted` — your party invite was accepted
  - `party_invite_declined` — your party invite was declined
  - `party_kicked` — you were removed from a party

  **Lobbies:**
  - `lobby_kicked` — you were removed from a lobby

  **Achievements:**
  - `achievement_unlocked` — you unlocked an achievement

  **Chat** (via `create_chat_notification`, includes `message_count` in metadata):
  - `chat_friend` — new friend DM messages
  - `chat_group` — new group chat messages
  - `chat_lobby` — new lobby chat messages
  - `chat_party` — new party chat messages

- Invite cancellation retracts the original invite notification via `delete_notification_by/3` (friends, groups, parties).
- API endpoints: `GET /api/v1/notifications`, `POST /api/v1/notifications`, `PUT /api/v1/notifications/:id/read`, `DELETE /api/v1/notifications`.

### PubSub & Real-time conventions

- PubSub topics follow the pattern `"resource:<id>"` for instance topics and `"resources"` for collection topics:
  - `"lobby:<id>"` / `"lobbies"` — lobby events (member join/leave, updates)
  - `"group:<id>"` / `"groups"` — group events (member join/leave, requests, updates)
  - `"party:<id>"` / `"parties"` — party events (member join/leave, updates)
  - `"user:<id>"` — user-specific events (friend requests, notifications, friend DM chat, achievement unlock/progress)
  - `"achievements"` — global achievement events (definition changes, unlocks for admin dashboards)
  - `"chat:lobby:<id>"` — lobby chat messages
  - `"chat:group:<id>"` — group chat messages
  - `"chat:friend:<low>:<high>"` — friend DM chat (sorted user id pair)
- WebSocket channels mirror PubSub topics: `UserChannel`, `LobbyChannel`, `LobbiesChannel`, `GroupChannel`, `GroupsChannel`, `PartyChannel`.
- LiveViews subscribe to PubSub topics directly (not via channels) using context `subscribe_*` functions.

### WebRTC DataChannels

- WebRTC provides low-latency DataChannels alongside the existing WebSocket. The server acts as a WebRTC peer (not P2P between clients).
- **Required dependency**: `ex_webrtc` and `ex_sctp` are required deps in `game_server_web`. WebRTC signaling handlers are always compiled in.
- **Rust requirement**: `ex_sctp` (required for DataChannels) compiles a Rust NIF. Local dev needs `rustup`. Docker/CI need Rust toolchain added.
- **Signaling over UserChannel**: No new channel. The existing authenticated `UserChannel` handles SDP/ICE exchange via events:
  - Client → Server: `"webrtc:offer"`, `"webrtc:ice"`, `"webrtc:send"`, `"webrtc:close"`
  - Server → Client: `"webrtc:answer"`, `"webrtc:ice"`, `"webrtc:data"`, `"webrtc:channel_open"`, `"webrtc:channel_closed"`, `"webrtc:state"`
- **Auth inherited from WebSocket**: The `PeerConnection` is created inside an authenticated channel process. No separate WebRTC auth.
- **One PeerConnection per user**: Managed by `GameServerWeb.WebRTCPeer` GenServer, linked to the channel process. Stored in channel assigns as `:webrtc_peer`.
- **WebSocket stays open**: Both transports coexist. WebSocket handles signaling/notifications/chat. WebRTC handles game-specific data.
- **DataChannel strategy**: Clients create named channels — `"events"` (reliable, ordered) for important game events, `"state"` (unreliable, unordered) for high-frequency position sync.
- **Config**: `config :game_server_web, :webrtc, enabled: true, ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]`
- **Client helpers**: `assets/js/webrtc.js` (browser), `clients/gamend_template/GamendWebRTC.gd` (Godot)
- **Design document**: `docs/webrtc-design.md`

### Caching conventions

- App cache is `GameServer.Cache` (Nebulex 3, multilevel: local L1 + optional Redis/partitioned L2). **Nebulex 3 returns `{:ok, value}` tuples** — use `GameServer.Cache.get!/1` (raw value, `nil` on miss) or `fetch/1`, never bare `get/1` compared against raw values.
- Read caching uses **version keys**: cache keys embed a `*_cache_version(...)` counter read via `get!(...) || 1`; invalidation = `incr` the counter. Data entries must carry a TTL (typically 60s) — that TTL is the cross-instance staleness bound.
- When a stale read would be *incorrect* (not merely briefly outdated) — cached users gating auth, sessions, tokens, KV values — invalidate with `GameServer.Cache.invalidate/1` (delete + PubSub broadcast; `GameServer.Cache.Sync` evicts the key from other instances' L1) instead of `delete/1`.
- Cache user structs only via `Accounts.cache_user/1`; never `Cache.put` the `{:accounts, :user, id}` key directly.

### Advisory locks

- Used for atomic join/leave/create operations on lobbies, groups, and parties.
- Namespace convention: lobby → 1, group → 2, party → 3.
- Implemented via `GameServer.Repo.advisory_lock/2` wrapping the operation in a transaction.

### Pagination (repository convention)

- Pattern: Use opt-in page & page_size query params for list endpoints. This is a simple limit/offset style pagination.
- Defaults: If not provided, default page = 1 and page_size = 25 unless an endpoint documents a different default.
- Response shape: list endpoints must return a JSON object containing `data` (array) and `meta` (object). `meta` SHOULD include:
  - page: current page (integer)
  - page_size: the page size used (integer)
  - count: number of items on the returned page
  - total_count: total number of matching items (use domain-level count helpers)
  - total_pages: number of pages (computed: ceil(total_count / page_size))
  - has_more: boolean (true when page < total_pages — exact, not a heuristic)

- Domain responsibilities: Add a lightweight count helper for list endpoints (eg. Accounts.count_search_users/1, Friends.count_friends_for_user/1, Lobbies.count_list_lobbies/1). Controllers should use these helpers to populate `total_count` without pulling all rows.

- UI & LiveViews: When rendering paginated lists in LiveViews or admin UIs, show "page X / Y (N total)" using the `meta` fields and disable/enable the Prev/Next buttons based on page/total_pages.

Example response:

```
{
  "data": [...],
  "meta": {
    "page": 1,
    "page_size": 25,
    "count": 25,
    "total_count": 946,
    "total_pages": 38,
    "has_more": true
  }
}
```

<!-- phoenix-gen-auth-end -->

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        # reset the stream with the new messages
        |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->

## Feature addition checklist

When adding a new feature or domain resource, evaluate which of the following need updating. Not every feature requires all items — check based on whether the feature needs web UI, API, admin, or docs.

### Always required
- [ ] **Context module** (`apps/game_server_core/lib/game_server/`): domain logic, Ecto schemas, changesets, queries
- [ ] **Migrations** (`apps/game_server_core/priv/repo/migrations/`): database schema changes
- [ ] **Tests**: context tests + controller/LiveView tests. Run `mix precommit` when done

### If the feature has an API
- [ ] **API controller** (`apps/game_server_web/lib/game_server_web/controllers/api/v1/`): REST endpoints
- [ ] **OpenApiSpex** (inline `operation/2` macros in the controller): document request/response schemas. The spec is generated at runtime from code — no standalone YAML/JSON file
- [ ] **API JSON view/serialization**: ensure response shapes follow pagination convention when listing (`data` + `meta`)
- [ ] **Router** (`apps/game_server_web/lib/game_server_web/router/shared.ex` for API routes, `router/browser_routes.ex` for browser routes; the host router is `lib/game_server_host/router.ex`): add routes in the appropriate scope (`:api` public or `:api_auth` authenticated or `:api_admin` admin)

### If the feature has admin management
- [ ] **Admin API controller** (`apps/game_server_web/lib/game_server_web/controllers/api/v1/admin/`): admin-only endpoints
- [ ] **Admin LiveView** (`apps/game_server_web/lib/game_server_web/live/admin_live/`): admin dashboard page for managing the resource
- [ ] **Admin route** (router, inside `live_session :require_authenticated_admin`): add LiveView route

### If the feature has a public web page
- [ ] **Public LiveView** (`apps/game_server_web/lib/game_server_web/live/`): public-facing page (e.g., GroupsLive, LeaderboardsLive)
- [ ] **Nav link** (`apps/game_server_web/lib/game_server_web/components/layouts.ex`): add navigation link in **all 4 locations** (desktop auth, desktop unauth, mobile auth, mobile unauth)
- [ ] **Route** (router, inside `live_session :current_user` for public or `:require_authenticated_user` for auth-only)

### If the feature has real-time updates
- [ ] **PubSub** (in the context module): `broadcast/3` calls + `subscribe_*/0` functions. Follow topic naming: `"resource:<id>"` and `"resources"`
- [ ] **WebSocket channel** (`apps/game_server_web/lib/game_server_web/channels/`): if clients need socket-based real-time updates
- [ ] **Channel route** (in `user_socket.ex`): register the channel

### If the feature needs documentation
- [ ] **Public docs guide** (`apps/game_server_web/lib/game_server_web/live/public_docs/`): add a `.html.heex` template — it is auto-discovered via `embed_templates`
- [ ] **Sidebar entry** (`apps/game_server_web/lib/game_server_web/live/public_docs.ex`): add link in the docs sidebar navigation
- [ ] **This instructions file** (`.github/copilot-instructions.md`): update domain-specific sections with the new feature's conventions

### Domain conventions to follow
- Use advisory locks (namespace 1=lobby, 2=group, 3=party) for atomic join/leave operations
- Add `blocked?/2` checks on invite operations to prevent inviting blocked users
- Add lightweight `count_*` helpers for paginated list endpoints
- Context list functions should support keyword options: `:page`, `:page_size`, `:sort_by` and relevant filters
- **Always** update `CHANGELOG.md` when adding new features or making significant changes to existing functionality, especially if they affect configuration or public APIs.

## Project file organization

```
apps/
  game_server_core/           # Domain logic (contexts, schemas, migrations)
    lib/game_server/
      accounts.ex             # User accounts context
      friends.ex              # Friends & blocking context
      groups.ex               # Groups context
      lobbies.ex              # Lobbies context
      parties.ex              # Parties context
      leaderboards.ex         # Leaderboards context
      achievements.ex         # Achievements context
      notifications.ex        # Notifications context
      kv.ex                   # Key-value storage context
      hooks.ex                # Server scripting/hooks context
  game_server_web/            # Web layer (controllers, LiveViews, channels)
    lib/game_server_web/
      controllers/api/v1/     # Public API controllers (14 controllers)
      controllers/api/v1/admin/ # Admin API controllers (8 controllers)
      channels/               # WebSocket channels (6 channels) + webrtc_peer.ex
      live/                   # LiveViews (public + user auth)
      live/admin_live/        # Admin dashboard LiveViews (10 modules)
      live/public_docs/       # Documentation guide templates (20 guides)
      components/             # Shared components (layouts.ex, core_components.ex)
      auth/                   # Guardian JWT (guardian.ex, pipeline.ex)
  game_server_host/           # Runnable host app (router, boot config)
assets/                       # JS, CSS, vendor deps (incl. webrtc.js)
config/                       # Environment configs
docs/                         # Design documents (webrtc-design.md)
```

