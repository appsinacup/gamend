# gamend_core v1.0.1211 - API Reference

## Modules

- [Gamend](Gamend.md): Gamend keeps the contexts that define your domain
and business logic.
- [Gamend.Analytics](Gamend.Analytics.md): The one place aggregate numbers come from. Four families
- [Gamend.Analytics.ActivityDay](Gamend.Analytics.ActivityDay.md): A user was seen on a UTC day. One row per `(user_id, day)`; written once by
`Gamend.Analytics.record_activity/2`, never updated.

- [Gamend.Analytics.DailyCount](Gamend.Analytics.DailyCount.md): A named counter for one UTC day. Keys are free-form dotted strings owned by
the game (`"level.finished"`, `"level.started.lang:ja"`); the engine only
stores and sums them. Written by `Gamend.Analytics.count/3`.

- [Gamend.ApiConventions](Gamend.ApiConventions.md): Mechanical checks for the conventions in `docs/specs/api-conventions.md`.
- [Gamend.Captcha](Gamend.Captcha.md): Human verification for the unauthenticated browser forms, via
[Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/).
- [Gamend.ClientLogs](Gamend.ClientLogs.md): Logs from the game client, put where the server's own logs already are.
- [Gamend.ClientLogs.Session](Gamend.ClientLogs.Session.md): One run of the game on one device, as seen from the server.
- [Gamend.ClientLogs.SessionLobby](Gamend.ClientLogs.SessionLobby.md): A lobby a client session was in.
- [Gamend.Cluster](Gamend.Cluster.md): Erlang distribution, needed for multi-node deployments and the partitioned
L2 cache.
- [Gamend.Database](Gamend.Database.md): Connection and tuning settings for `Gamend.Repo`.
- [Gamend.Mail](Gamend.Mail.md): Outbound email transport.
- [Gamend.Policy](Gamend.Policy.md): One question — "may this user do this to this thing?" — asked the same way
everywhere.
- [Gamend.Presence](Gamend.Presence.md): Cluster-wide tracking of who is connected where.
- [Gamend.Release](Gamend.Release.md): Release-time equivalents of the `host.*` mix tasks.
- [Gamend.Signaling](Gamend.Signaling.md): WebRTC signaling: who is in a room, and relaying offers between them.
- [Gamend.Signals](Gamend.Signals.md): Server-side signals: a plugin emits a named event, another part of the plugin
waits for it.
- [Gamend.Time](Gamend.Time.md): The server's wall clock, in milliseconds since the epoch, for sending to
clients.

- Accounts
  - [Gamend.Accounts](Gamend.Accounts.md): The Accounts context.
  - [Gamend.Accounts.AgePolicy](Gamend.Accounts.AgePolicy.md): What a user's age permits.
  - [Gamend.Accounts.AvatarMirror](Gamend.Accounts.AvatarMirror.md): Oban worker that mirrors a user's external (OAuth provider) avatar into our
own object storage, so avatars render from our storage/CDN instead of
hotlinking the provider.
  - [Gamend.Accounts.InactivityNotifier](Gamend.Accounts.InactivityNotifier.md): Warns a user their account is about to be deleted for inactivity.
  - [Gamend.Accounts.PasswordHash](Gamend.Accounts.PasswordHash.md): Password hashing: Argon2id for new hashes, bcrypt still accepted for old ones.
  - [Gamend.Accounts.PresenceStatus](Gamend.Accounts.PresenceStatus.md): How recently a user was seen, as the three states the UI actually draws.
  - [Gamend.Accounts.PresenceWriter](Gamend.Accounts.PresenceWriter.md): Coalesces `users.is_online` transitions into one write per flush window.
  - [Gamend.Accounts.Scope](Gamend.Accounts.Scope.md): Defines the scope of the caller to be used throughout the app.
  - [Gamend.Accounts.StalePresenceSweeper](Gamend.Accounts.StalePresenceSweeper.md): Periodically sweeps users whose `is_online` flag is `true` but whose
`last_seen_at` timestamp is older than a configurable threshold.
  - [Gamend.Accounts.User](Gamend.Accounts.User.md): The User schema and associated changeset functions used across the
application (registration, OAuth, and admin changes).
  - [Gamend.Accounts.UserNotifier](Gamend.Accounts.UserNotifier.md): Small helpers used to deliver transactional emails for the Accounts flow
(confirmation, magic link, and email change instructions).
  - [Gamend.Accounts.UserToken](Gamend.Accounts.UserToken.md): Functions and schema for persistent user tokens used by sessions, magic links,
and email-change workflows.
  - [Gamend.Accounts.UsernameGenerator](Gamend.Accounts.UsernameGenerator.md): Generates default usernames for new users.
  - [Gamend.Apple](Gamend.Apple.md): Apple OAuth client secret generation for Ueberauth.
  - [Gamend.OAuth.Exchanger](Gamend.OAuth.Exchanger.md): Default implementation for exchanging OAuth codes with providers.
  - [Gamend.OAuth.GoogleIDToken](Gamend.OAuth.GoogleIDToken.md): Verifies Google OpenID Connect `id_token`s for native/mobile sign-in flows.
  - [Gamend.OAuth.Providers](Gamend.OAuth.Providers.md): Credentials and availability for the social sign-in providers.
  - [Gamend.OAuthSession](Gamend.OAuthSession.md): Simple Ecto schema for OAuth session polling used by client SDKs.
  - [Gamend.OAuthSessions](Gamend.OAuthSessions.md): Helpers for creating and retrieving short-lived OAuth sessions.

- Lobbies
  - [Gamend.Lobbies](Gamend.Lobbies.md): Context module for lobby management: creating, updating, listing and searching lobbies.
  - [Gamend.Lobbies.Lobby](Gamend.Lobbies.Lobby.md): Ecto schema for the `lobbies` table and changeset helpers.
  - [Gamend.Lobbies.SpectatorTracker](Gamend.Lobbies.SpectatorTracker.md): Who is watching a lobby without being a member.
  - [Gamend.Lobbies.States](Gamend.Lobbies.States.md): The vocabulary a lobby's `state` commonly uses.
  - [Gamend.LobbySnapshots](Gamend.LobbySnapshots.md): Durable record of how a lobby's state evolved during a run.
  - [Gamend.LobbySnapshots.Blob](Gamend.LobbySnapshots.Blob.md): Content-addressed storage for one snapshot section.
  - [Gamend.LobbySnapshots.Event](Gamend.LobbySnapshots.Event.md): A decision worth explaining, recorded between two snapshots.
  - [Gamend.LobbySnapshots.Snapshot](Gamend.LobbySnapshots.Snapshot.md): One capture of a lobby's state at a mutation entry point.
  - [Gamend.LobbySnapshots.Writer](Gamend.LobbySnapshots.Writer.md): Buffers snapshots and events and bulk-inserts them.

- Matchmaking
  - [Gamend.Matchmaking](Gamend.Matchmaking.md): Public API for the built-in matchmaking system.
  - [Gamend.Matchmaking.Broadcast](Gamend.Matchmaking.Broadcast.md): Broadcasts matchmaking events to users.
  - [Gamend.Matchmaking.Constants](Gamend.Matchmaking.Constants.md): Constants for the matchmaking system.

  - [Gamend.Matchmaking.Match](Gamend.Matchmaking.Match.md): Creates the lobby for a claimed match and notifies the players.
  - [Gamend.Matchmaking.Matcher](Gamend.Matchmaking.Matcher.md): Match-forming logic for a group of tickets that share the same
`match_params`.
  - [Gamend.Matchmaking.Ticket](Gamend.Matchmaking.Ticket.md): Ecto schema for a matchmaking ticket.
  - [Gamend.Matchmaking.Worker](Gamend.Matchmaking.Worker.md): Periodic driver for the matchmaking sweep.
  - [Gamend.ReadyChecks](Gamend.ReadyChecks.md): Ready checks: *these players must each answer before this proceeds*.
  - [Gamend.ReadyChecks.Check](Gamend.ReadyChecks.Check.md): Ecto schema for one ready check — a *moment* at which a set of players must
each answer before something proceeds.
  - [Gamend.ReadyChecks.Participant](Gamend.ReadyChecks.Participant.md): Ecto schema for one player's answer inside a ready check.

- Social
  - [Gamend.Chat](Gamend.Chat.md): Context for chat messaging across lobbies, groups, and friend DMs.
  - [Gamend.Chat.FilterWord](Gamend.Chat.FilterWord.md): Ecto schema for the `chat_filter_words` table — one entry of the chat word
blocklist.
  - [Gamend.Chat.Message](Gamend.Chat.Message.md): Ecto schema for the `chat_messages` table.
  - [Gamend.Chat.Moderation](Gamend.Chat.Moderation.md): Chat word filter and mutes.
  - [Gamend.Chat.Moderation.Cache](Gamend.Chat.Moderation.Cache.md): Node-local hot path for chat moderation: the word blocklist and active mutes.
  - [Gamend.Chat.Moderation.Normalizer](Gamend.Chat.Moderation.Normalizer.md): Canonical form for chat filter matching.
  - [Gamend.Chat.Moderation.Notices](Gamend.Chat.Moderation.Notices.md): The notifications chat moderation sends: alerting admins that a report landed,
warning a player, telling a player they were muted, and telling a reporter
what came of their report.
  - [Gamend.Chat.Moderation.Sync](Gamend.Chat.Moderation.Sync.md): Keeps the node-local chat-moderation ETS tables in sync with the database and
the other app instances, and sweeps expired mutes.
  - [Gamend.Chat.Mute](Gamend.Chat.Mute.md): Ecto schema for the `chat_mutes` table — a silenced chat sender.
  - [Gamend.Chat.ReadCursor](Gamend.Chat.ReadCursor.md): Ecto schema for the `chat_read_cursors` table.
  - [Gamend.Chat.Report](Gamend.Chat.Report.md): Ecto schema for the `chat_reports` table — a player- or filter-filed report
about a chat message.
  - [Gamend.Chat.Reports](Gamend.Chat.Reports.md): The chat report queue.
  - [Gamend.Friends](Gamend.Friends.md): Friends context - handles friend requests and relationships.
  - [Gamend.Friends.Friendship](Gamend.Friends.Friendship.md): Ecto schema representing a friendship/request between two users.
  - [Gamend.Groups](Gamend.Groups.md): Context module for group management: creating, updating, listing, joining,
leaving, kicking, promoting/demoting members, and handling join requests.
  - [Gamend.Groups.Group](Gamend.Groups.Group.md): Ecto schema for the `groups` table.
  - [Gamend.Groups.GroupInvite](Gamend.Groups.GroupInvite.md): Ecto schema for the `group_invites` table.
  - [Gamend.Groups.GroupJoinRequest](Gamend.Groups.GroupJoinRequest.md): Ecto schema for the `group_join_requests` table.
  - [Gamend.Groups.GroupMember](Gamend.Groups.GroupMember.md): Ecto schema for the `group_members` join table.
  - [Gamend.Groups.Invites](Gamend.Groups.Invites.md): Group invitations: creating, accepting, declining, cancelling, and
listing/counting pending invites.
  - [Gamend.Groups.JoinRequests](Gamend.Groups.JoinRequests.md): Join requests for private groups: requesting, listing, approving,
rejecting, and cancelling.
  - [Gamend.Parties](Gamend.Parties.md): Context module for party management.
  - [Gamend.Parties.Party](Gamend.Parties.Party.md): Ecto schema for the `parties` table.
  - [Gamend.Parties.PartyInvite](Gamend.Parties.PartyInvite.md): Ecto schema for the `party_invites` table.

- Progression
  - [Gamend.Leaderboards](Gamend.Leaderboards.md): The Leaderboards context.
  - [Gamend.Leaderboards.Leaderboard](Gamend.Leaderboards.Leaderboard.md): Ecto schema for the `leaderboards` table.
  - [Gamend.Leaderboards.Record](Gamend.Leaderboards.Record.md): Ecto schema for the `leaderboard_records` table.
  - [Gamend.Quests](Gamend.Quests.md): Event-driven quest/progression engine.
  - [Gamend.Quests.Objective](Gamend.Quests.Objective.md): One objective inside a quest definition: reach `target` occurrences of
`event` (as reported through `Gamend.Quests.report_event/4`).
  - [Gamend.Quests.Quest](Gamend.Quests.Quest.md): Ecto schema for the `quests` table.
  - [Gamend.Quests.QuestProgress](Gamend.Quests.QuestProgress.md): Ecto schema for the `quest_progress` table — one row per user, quest and
reset period.
  - [Gamend.Quests.Reward](Gamend.Quests.Reward.md): One reward entry on a quest definition: `amount` of a currency
(via `Gamend.Economy.grant/4`) or an item
(via `Gamend.Inventory.grant_item/4`).

  - [Gamend.Tournaments](Gamend.Tournaments.md): Bracket tournaments: registration → seeded single-elimination draw → timed
rounds → champions. See TOURNAMENT_DESIGN.md.
  - [Gamend.Tournaments.Entry](Gamend.Tournaments.Entry.md): One side of the bracket: a leader and their tournament progress.
  - [Gamend.Tournaments.Match](Gamend.Tournaments.Match.md): A pairing plus a verdict: two entries that must produce a winner by
`deadline_at`. Never a lobby — how the pairing is played is game policy;
`metadata` is game scratch space (runs, lobby id, ...).

  - [Gamend.Tournaments.Ticker](Gamend.Tournaments.Ticker.md): Periodic driver for tournament lifecycles: state transitions, match-ready
firing, deadline_at sweeps and recurrence spawns (`Gamend.Tournaments.tick/0`).
  - [Gamend.Tournaments.Tournament](Gamend.Tournaments.Tournament.md): A bracket tournament occurrence.

- Economy
  - [Gamend.Economy](Gamend.Economy.md): Virtual-currency wallets with an append-only ledger.
  - [Gamend.Economy.LedgerEntry](Gamend.Economy.LedgerEntry.md): Append-only record of a single wallet change (grant, spend, transfer, admin
adjustment). One row per balance mutation, keeping an auditable history.

  - [Gamend.Economy.Wallet](Gamend.Economy.Wallet.md): A user's balance of one currency. Currencies are free-form string codes
(`"gold"`, `"gems"`, `"energy"`) — the game decides which exist.

  - [Gamend.Inventory](Gamend.Inventory.md): Player item stacks — the non-fungible companion to `Gamend.Economy`.
  - [Gamend.Inventory.Item](Gamend.Inventory.Item.md): A user's stack of one item. Items are free-form string codes
(`"health_potion"`, `"sword"`, `"card_374"`) — the game decides which exist.
`metadata` holds per-stack properties.

  - [Gamend.Inventory.LedgerEntry](Gamend.Inventory.LedgerEntry.md): Append-only record of a single item-stack change (grant, consume, admin
adjustment) — the inventory counterpart of `Gamend.Economy.LedgerEntry`.
Carries the `idempotency_key` that makes item grants safe to retry.

  - [Gamend.Payments](Gamend.Payments.md): Payment catalog, purchase ledger, and entitlements.
  - [Gamend.Payments.Entitlement](Gamend.Payments.Entitlement.md): User access grant derived from a purchase or admin/server action.

  - [Gamend.Payments.Product](Gamend.Payments.Product.md): Internal product sold by one or more payment providers.

  - [Gamend.Payments.ProviderConfig](Gamend.Payments.ProviderConfig.md): Runtime payment-provider configuration helpers.
  - [Gamend.Payments.ProviderEvent](Gamend.Payments.ProviderEvent.md): Dedupe record for webhook and store notification events.

  - [Gamend.Payments.ProviderProduct](Gamend.Payments.ProviderProduct.md): Maps an internal product to a provider-specific SKU or price id.

  - [Gamend.Payments.Providers.Apple](Gamend.Payments.Providers.Apple.md): App Store Server API and StoreKit 2 adapter.
  - [Gamend.Payments.Providers.Apple.JWS](Gamend.Payments.Providers.Apple.JWS.md): Verifies App Store JWS payloads (StoreKit signed transactions and App Store
Server Notifications V2).
  - [Gamend.Payments.Providers.Google](Gamend.Payments.Providers.Google.md): Google Play Billing adapter.
  - [Gamend.Payments.Providers.Steam](Gamend.Payments.Providers.Steam.md): Steam MicroTxn adapter.
  - [Gamend.Payments.Providers.Stripe](Gamend.Payments.Providers.Stripe.md): Minimal Stripe Checkout and webhook adapter.

  - [Gamend.Payments.Purchase](Gamend.Payments.Purchase.md): Provider transaction record.

  - [Gamend.Payments.ReconciliationCursor](Gamend.Payments.ReconciliationCursor.md): Provider reconciliation checkpoint.

  - [Gamend.Payments.Settings](Gamend.Payments.Settings.md): Store credentials, per provider.

- Storage &amp; content
  - [Gamend.Content](Gamend.Content.md): Reads and renders Markdown content from project files and directories.
  - [Gamend.ContentSettings](Gamend.ContentSettings.md): Where the server finds host-supplied content: the theme config, hook plugins,
and the GeoIP database.

  - [Gamend.KV](Gamend.KV.md): Generic key/value storage.
  - [Gamend.Settings](Gamend.Settings.md): The declared configuration surface: every setting core, the host and its
plugins expose, with its type, default, group, env var name and required
level.
  - [Gamend.Settings.Provider](Gamend.Settings.Provider.md): Declares a group of settings on a module.
  - [Gamend.Storage](Gamend.Storage.md): Object storage for user uploads (avatars, and future user-generated content).
  - [Gamend.Storage.Adapter](Gamend.Storage.Adapter.md): Behaviour for object-storage backends.
  - [Gamend.Storage.Local](Gamend.Storage.Local.md): Disk-backed storage — the default backend.
  - [Gamend.Storage.S3](Gamend.Storage.S3.md): S3-compatible storage via ExAws.
  - [Gamend.Theme](Gamend.Theme.md): Behaviour for pluggable site theming providers.
  - [Gamend.Theme.JSONConfig](Gamend.Theme.JSONConfig.md): JSON-backed Theme provider. Reads **one** config file — from the
`GAMEND_CONTENT_THEME_CONFIG` setting or the host-owned default path — and
translates its text through gettext at read time.
  - [Gamend.Theme.Translatable](Gamend.Theme.Translatable.md): Which leaves of a theme config are text, and which are configuration.

- Delivery
  - [Gamend.Notifications](Gamend.Notifications.md): Notifications context – create, list, and delete persisted user-to-user
notifications.
  - [Gamend.Notifications.Notification](Gamend.Notifications.Notification.md): Ecto schema representing a notification sent from one user to another.
  - [Gamend.Notifications.Types](Gamend.Notifications.Types.md): The `metadata["type"]` codes a notification may carry.
  - [Gamend.Push](Gamend.Push.md): Push context – device push-token registry and (see `send_to_user/3`)
server-authoritative delivery of push notifications.
  - [Gamend.Push.APNSDispatcher](Gamend.Push.APNSDispatcher.md): Pigeon dispatcher for APNs. Configured by `host_runtime.exs` from the
`APNS_*` env vars; started by `Gamend.Push.Supervisor` only when that
config exists.

  - [Gamend.Push.DeliveryWorker](Gamend.Push.DeliveryWorker.md): Delivers one push message to one token. One job per token is deliberate:
FCM v1 and APNs are one-request-per-token anyway, and it buys exact
per-token Oban retry/backoff — a half-delivered batch job would re-push
duplicates on retry.
  - [Gamend.Push.FCMDispatcher](Gamend.Push.FCMDispatcher.md): Pigeon dispatcher for FCM. Configured by `host_runtime.exs` from the
`PUSH_FCM_*` env vars; started by `Gamend.Push.Supervisor` only when
that config exists.

  - [Gamend.Push.FanoutWorker](Gamend.Push.FanoutWorker.md): Expands a multi-user send into per-token `DeliveryWorker` jobs, in chunks,
off the caller's request path. `Gamend.Push.send_to_users/3` enqueues
this above its inline threshold so a large broadcast never holds a long
transaction (SQLite is single-writer) and survives restarts. Identical args
within a minute dedupe via Oban uniqueness (double-broadcast guard).

  - [Gamend.Push.Message](Gamend.Push.Message.md): A validated push message: what `Gamend.Push.send_to_user/3` accepts and
what the delivery workers carry through job args.
  - [Gamend.Push.Provider](Gamend.Push.Provider.md): Behaviour for push delivery providers.
  - [Gamend.Push.Providers.APNs](Gamend.Push.Providers.APNs.md): APNs-direct provider for iOS, delivered through the
`Gamend.Push.APNSDispatcher` Pigeon dispatcher (token-auth `.p8`,
HTTP/2 over Mint). The `apns-topic` comes from `APNS_TOPIC`.

  - [Gamend.Push.Providers.FCM](Gamend.Push.Providers.FCM.md): Firebase Cloud Messaging (HTTP v1) provider for Android and Web — and iOS
relay, if a game prefers Firebase over APNs-direct — delivered through the
`Gamend.Push.FCMDispatcher` Pigeon dispatcher, authenticated by the
`Gamend.Push.Goth` worker.

  - [Gamend.Push.Providers.Log](Gamend.Push.Providers.Log.md): Zero-config default provider: logs each delivery instead of calling out —
the `Storage.Local` of push. Every token routed here (nothing configured,
`PUSH_ADAPTER=log`, or a provider whose dispatcher is down) reports success,
so the whole flow is exercisable with no credentials.

  - [Gamend.Push.PushToken](Gamend.Push.PushToken.md): Ecto schema for a registered device push token.
  - [Gamend.Push.Supervisor](Gamend.Push.Supervisor.md): Supervises the push delivery processes: the Goth worker (FCM OAuth) and the
two Pigeon dispatchers.
  - [Gamend.Realtime](Gamend.Realtime.md): Pushing game-defined realtime events to a player's socket.

- Plugins
  - [Gamend.Hooks](Gamend.Hooks.md): Behaviour for application-level hooks / callbacks.
  - [Gamend.Hooks.Declarations](Gamend.Hooks.Declarations.md): Registry of what a plugin *declares* it contributes, for observability and
validation.
  - [Gamend.Hooks.Default](Gamend.Hooks.Default.md): Default no-op implementation for Gamend.Hooks
  - [Gamend.Hooks.DynamicRpcs](Gamend.Hooks.DynamicRpcs.md): Runtime registry for *dynamic* RPC function names exported by hook plugins.
  - [Gamend.Hooks.HookSchemas](Gamend.Hooks.HookSchemas.md): Registry of game-defined protobuf schemas for typed hooks, plus the
argument/result conversion that makes typed hooks callable from every
transport and payload format.
  - [Gamend.Hooks.KvSchemas](Gamend.Hooks.KvSchemas.md): Registry of game-defined protobuf schemas for KV entry data.
  - [Gamend.Hooks.MetadataSchemas](Gamend.Hooks.MetadataSchemas.md): Registry of game-defined protobuf schemas for entity metadata.
  - [Gamend.Hooks.PluginBuilder](Gamend.Hooks.PluginBuilder.md): Builds an OTP plugin bundle from plugin source code on disk.
  - [Gamend.Hooks.PluginManager](Gamend.Hooks.PluginManager.md): Loads and manages hook plugins shipped as OTP applications under `modules/plugins/*`.
  - [Gamend.Hooks.PluginManager.Plugin](Gamend.Hooks.PluginManager.Plugin.md): A loaded plugin descriptor.

- Operations
  - [Gamend.Async](Gamend.Async.md): Utilities for running best-effort background work.
  - [Gamend.Cache](Gamend.Cache.md): Application cache backed by Nebulex.
  - [Gamend.Cache.L1](Gamend.Cache.L1.md): L1 cache (local, in-memory).
  - [Gamend.Cache.L2.Partitioned](Gamend.Cache.L2.Partitioned.md): L2 cache (partitioned topology).
  - [Gamend.Cache.L2.Partitioned.Primary](Gamend.Cache.L2.Partitioned.Primary.md): This is the cache for the primary storage.

  - [Gamend.Cache.L2.Redis](Gamend.Cache.L2.Redis.md): L2 cache backed by Redis.
  - [Gamend.Cache.Settings](Gamend.Cache.Settings.md): Cache topology. The resolved levels are built from these in the host's
runtime config; `Gamend.Cache` itself holds the assembled structure.

  - [Gamend.Cache.Stats](Gamend.Cache.Stats.md): Lightweight in-memory counters for cache effectiveness and overload signals,
aggregated from telemetry events
  - [Gamend.Cache.Sync](Gamend.Cache.Sync.md): Applies cache invalidations broadcast by other app instances.
  - [Gamend.Config](Gamend.Config.md): Typed reads of environment variables a plugin declared via `env_vars/0`.
  - [Gamend.IpBans](Gamend.IpBans.md): Persistence for IP bans.
  - [Gamend.IpBans.IpBan](Gamend.IpBans.IpBan.md): A persisted IP ban. `expires_at` is `nil` for permanent bans.

  - [Gamend.Jobs](Gamend.Jobs.md): Durable background jobs, backed by Oban.
  - [Gamend.Limits](Gamend.Limits.md): Central module for configurable validation limits.
  - [Gamend.Lock](Gamend.Lock.md): Serialized execution using database-level advisory locks.
  - [Gamend.Lock.Local](Gamend.Lock.Local.md): Reentrant, cluster-wide keyed mutex — the non-Postgres half of
`Gamend.Lock.serialize/3`.
  - [Gamend.Mailer](Gamend.Mailer.md)
  - [Gamend.Repo](Gamend.Repo.md)
  - [Gamend.Repo.AdvisoryLock](Gamend.Repo.AdvisoryLock.md): Advisory locking for protecting TOCTOU (Time-of-Check-Time-of-Use) patterns.
  - [Gamend.Repo.MigrationPaths](Gamend.Repo.MigrationPaths.md): Resolves every migration directory that belongs to a gamend deployment.
  - [Gamend.Retention](Gamend.Retention.md): Periodically prunes old rows from unbounded tables.
  - [Gamend.Schedule](Gamend.Schedule.md): Dynamic cron-like job scheduling for hooks.

- Internals
  - [Gamend.Proto.GodobufPresence](Gamend.Proto.GodobufPresence.md): Fixes proto3-optional presence checks in godobuf-generated GDScript.
  - [Gamend.Schema](Gamend.Schema.md): Shared schema base: `use Gamend.Schema` instead of `use Ecto.Schema`.
  - [Gamend.SchemaJSON](Gamend.SchemaJSON.md): JSON encoding for Ecto schemas under the API's null policy: string fields
encode as `""` when nil and map fields as `%{}` — game clients (Godot in
particular) choke on `null` where they expect a string. Datetimes, numbers
and booleans keep `null`, where absence is semantic.
  - [Gamend.Types](Gamend.Types.md): Shared types used across Gamend contexts.
  - [Gamend.UUIDv7](Gamend.UUIDv7.md): UUIDv7 Ecto type used for all primary and foreign keys.

## Mix Tasks

- [mix demo.seed](Mix.Tasks.Demo.Seed.md): Fills the database with enough demo data to exercise pagination and the
list/detail pages at realistic sizes.
- [mix gamend.api.lint](Mix.Tasks.Gamend.Api.Lint.md): Enforces the naming and serialization conventions mechanically.
- [mix gamend.content.extract](Mix.Tasks.Gamend.Content.Extract.md): Writes `content.pot` from the titles and descriptions stored on quests,
leaderboards and tournaments.
- [mix gamend.content.migrate_metadata](Mix.Tasks.Gamend.Content.MigrateMetadata.md): One-shot migration for instances that stored translations in the database.
- [mix gamend.settings.env_example](Mix.Tasks.Gamend.Settings.EnvExample.md): Writes `.env.example` from `Gamend.Settings.all/0`, grouped and
commented from each setting's declaration.
- [mix gamend.settings.guide](Mix.Tasks.Gamend.Settings.Guide.md): Writes the public Settings guide from `Gamend.Settings.all/0`.
- [mix gamend.theme.extract](Mix.Tasks.Gamend.Theme.Extract.md): Writes `theme.pot` from the strings in the theme config.
- [mix gamend.theme.migrate_locales](Mix.Tasks.Gamend.Theme.MigrateLocales.md): One-shot migration off one-JSON-file-per-locale.
- [mix gen.sdk](Mix.Tasks.Gen.Sdk.md): Generates SDK stub modules from the real Gamend modules.
- [mix host.proto.check](Mix.Tasks.Host.Proto.Check.md): Check that registered protobuf schemas actually match the JSON they encode.
- [mix host.proto.gen](Mix.Tasks.Host.Proto.Gen.md): Generates protobuf bindings for every target from a `.proto` file.

