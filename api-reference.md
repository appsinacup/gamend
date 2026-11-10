# gamend_core v1.1.1415 - API Reference

## Modules

- [Gamend](Gamend.md): Gamend keeps the contexts that define your domain
and business logic.
- [Gamend.AccountRequired](Gamend.AccountRequired.md): What a guest may not do until it registers. A guest is an account with no
email and no sign-in provider, only a device or a browser
(`Gamend.Accounts.User.anonymous?/1`). The host picks the features
- [Gamend.AfterCommit](Gamend.AfterCommit.md): Side effects that wait for the enclosing transaction to commit.
- [Gamend.Analytics](Gamend.Analytics.md): The one place aggregate numbers come from. Four families
- [Gamend.Analytics.ActivityDay](Gamend.Analytics.ActivityDay.md): A user was seen on a UTC day. One row per `(user_id, day)`; written once by
`Gamend.Analytics.record_activity/2`, never updated.

- [Gamend.Analytics.Buffer](Gamend.Analytics.Buffer.md): Gathers `Gamend.Analytics` writes in ETS and lands them in batches: one
upsert per `(key, day)` counter and one `insert_all` for the events, every
`flush_ms`. A page view at twenty requests a second is otherwise a
database write per request, on the request's own connection.
- [Gamend.Analytics.Catalog](Gamend.Analytics.Catalog.md): What the analytics a game reports MEAN: which events and counters there
are, what each is called, which group it belongs to, which of its fields
are dimensions (a closed set to filter and break down by) and which are
numbers (to average). The admin Analytics pages read it to group, label
and offer filters; nothing is stored by it.
- [Gamend.Analytics.DailyCount](Gamend.Analytics.DailyCount.md): A named counter for one UTC day. Keys are free-form dotted strings owned by
the game (`"level.finished"`, `"level.started.lang:ja"`); the engine only
stores and sums them. Written by `Gamend.Analytics.count/3`.

- [Gamend.Analytics.Event](Gamend.Analytics.Event.md): One thing a player did, with who and when: `name` (`"web.game.finished"`),
`dims` (its fields — language, game, score — as a map with string keys),
`user_id` (nil for a visitor, nulled when the account is deleted) and
`inserted_at`, the moment it happened. Written by `Gamend.Analytics.track/3`
through `Gamend.Analytics.Buffer`, in batches, never one row at a time.
- [Gamend.Analytics.Explore](Gamend.Analytics.Explore.md): Reading the event rows (`analytics_events`) one question at a time: one
event, a group of them or all, over a range of UTC days, in one segment
(`Gamend.Analytics.Segment`), narrowed by any of the events' dimensions
(`lang = ro`, `mode = daily`) or to one account. The admin Analytics
pages' Explore and People tabs are built on it.
- [Gamend.Analytics.Segment](Gamend.Analytics.Segment.md): The ways the people numbers split: `:all`, `:registered` (an account with
an identity: an email, a provider) and `:guest` (an account backed by
nothing but a device or a browser, `Gamend.Accounts.User.anonymous?/1`).
A visitor with no account is in none of them: the daily counters count
them, no row does.
- [Gamend.Analytics.SegmentName](Gamend.Analytics.SegmentName.md): The analytics segments that are not everyone.

- [Gamend.ApiConventions](Gamend.ApiConventions.md): Mechanical checks for the conventions in `docs/specs/api-conventions.md`.
- [Gamend.Bans](Gamend.Bans.md): Bans: an IP address, an account or a chat sender kept out for a while, or
for good.
- [Gamend.Bans.Ban](Gamend.Bans.Ban.md): One ban: an IP address, an account or a chat sender kept out until
`expires_at` (`nil` is permanent), or until someone lifts it.
- [Gamend.Bans.BanKind](Gamend.Bans.BanKind.md): What a ban is against.

- [Gamend.Bans.BanScope](Gamend.Bans.BanScope.md): Where a chat ban applies.

- [Gamend.Bans.Cache](Gamend.Bans.Cache.md): Node-local hot path for `Gamend.Bans`: every active ban in ETS, keyed by its
target (`Gamend.Bans.Ban.target/4`, `{kind, subject, scope}`), read on each
request an IP ban covers and each chat message a mute covers.
- [Gamend.Bans.ExpiryWorker](Gamend.Bans.ExpiryWorker.md): Tells of a ban's end when it runs out (`Gamend.Bans.expire/1`): the
`after_ban_lifted/1` hook, and `account_unbanned` for an account.
- [Gamend.Bans.Sync](Gamend.Bans.Sync.md): Keeps the node-local ban table (`Gamend.Bans.Cache`) in step with the
database and the other app instances.
- [Gamend.Broadcast](Gamend.Broadcast.md): PubSub broadcasts that must never take the caller down with them.
- [Gamend.Captcha](Gamend.Captcha.md): Human verification for the unauthenticated browser forms, via
[Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/).
- [Gamend.ClientLogs](Gamend.ClientLogs.md): Logs from the game client, put where the server's own logs already are.
- [Gamend.ClientLogs.BuildKind](Gamend.ClientLogs.BuildKind.md): The kind of build a client log came from.

- [Gamend.ClientLogs.LogLevel](Gamend.ClientLogs.LogLevel.md): The levels of a client log.

- [Gamend.ClientLogs.Session](Gamend.ClientLogs.Session.md): One run of the game on one device, as seen from the server.
- [Gamend.ClientLogs.SessionLobby](Gamend.ClientLogs.SessionLobby.md): A lobby a client session was in.
- [Gamend.Cluster](Gamend.Cluster.md): Erlang distribution, needed for multi-node deployments and the partitioned
L2 cache.
- [Gamend.Codegen](Gamend.Codegen.md): Support for the `mix` tasks that write generated files into the repo.
- [Gamend.Containers](Gamend.Containers.md): Long-lived OCI containers, and the images they run, through the `podman` CLI.
- [Gamend.Database](Gamend.Database.md): Connection and tuning settings for `Gamend.Repo`.
- [Gamend.DemoSeed](Gamend.DemoSeed.md): Fills the database with enough demo data to exercise pagination and the
list/detail pages at realistic sizes.
- [Gamend.Export](Gamend.Export.md): A host's data as files another host can start from: what only the
application can copy.
- [Gamend.GitHub](Gamend.GitHub.md): The server's GitHub App: who may use which installation, the credentials a
job borrows from it, and what its webhook means.
- [Gamend.GitHub.API](Gamend.GitHub.API.md): The GitHub REST calls a GitHub App makes, and the credentials that make
them.
- [Gamend.GitHub.Installation](Gamend.GitHub.Installation.md): One user's access to one installation of the GitHub App.
- [Gamend.GitHub.Manifest](Gamend.GitHub.Manifest.md): The server's GitHub App, described once, so GitHub creates it rather than a
person filling in a form.
- [Gamend.HTTP](Gamend.HTTP.md): `Req` with the declared timeout and retries, for the calls core makes to other
services while a player waits: payment receipt checks (Apple, Google Play,
Steam), OAuth code exchanges, Google ID-token checks and avatar mirroring.
- [Gamend.HttpHeader](Gamend.HttpHeader.md): The header names core and its HTTP clients send.

- [Gamend.Icons](Gamend.Icons.md): The site's own icons, by name (`rocket-launch`): heroicons.com's 24px solid
set, read from the host's `heroicons` dependency when this compiles, the same
set the website draws (`GamendWeb.Icons`).
- [Gamend.Ledger](Gamend.Ledger.md): The mechanics both ledgered balances share: `Gamend.Economy` (currency in a
wallet) and `Gamend.Inventory` (quantity of an item).
- [Gamend.Ledger.LedgerReason](Gamend.Ledger.LedgerReason.md): The ledger reason recorded when a caller gave none.

- [Gamend.LiteralLint](Gamend.LiteralLint.md): Finds the strings that are really names: a status, an action, a kind, typed
out wherever it is used. `mix gamend.literal.lint` runs it.
- [Gamend.LocalHost](Gamend.LocalHost.md): The name a server uses for itself when no host is set.

- [Gamend.LocaleCode](Gamend.LocaleCode.md): A locale spoken in code: the default language.

- [Gamend.Mail](Gamend.Mail.md): Outbound email transport.
- [Gamend.MatchSeating](Gamend.MatchSeating.md): What a game decides for a formed match: where its players sit, and whether
they are asked first. `matchmaking_seat_match/1` answers with one
- [Gamend.Names](Gamend.Names.md): Names a closed set of strings: a macro for each value, so a pattern or a
guard can name one, and `all/0` for `validate_inclusion/3`.
- [Gamend.ParamType](Gamend.ParamType.md): The type names shown for an argument in the runtime pages.

- [Gamend.Parse](Gamend.Parse.md): Parsing and normalizing values that arrive from outside: request bodies, form
params, hook arguments, JSON.
- [Gamend.Placeholder](Gamend.Placeholder.md): The words a field holds when it has no real value to show.

- [Gamend.Policy](Gamend.Policy.md): One question — "may this user do this to this thing?" — asked the same way
everywhere.
- [Gamend.Presence](Gamend.Presence.md): Cluster-wide tracking of who is connected where.
- [Gamend.Query](Gamend.Query.md): Query-building pieces shared by the contexts. Right now: paging.
- [Gamend.RaceLint](Gamend.RaceLint.md): Source checks for the shapes that race: a rule ("one per player", "pays
once", "at most N", "only while pending") checked by a read and kept by a
write that does not look again. `mix gamend.race.lint` runs them.
- [Gamend.Rating](Gamend.Rating.md): Skill ratings, computed: Elo and Glicko-2, for two players, teams and
free-for-alls, and the gap a matcher accepts as a player waits
(priv/docs/40-gameplay/32-ratings.md).
- [Gamend.Release](Gamend.Release.md): Release-time equivalents of the `host.*` mix tasks.
- [Gamend.Release.Metadata](Gamend.Release.Metadata.md): What a release declares, written into its image as it is built, so a host
that runs the image from outside reads it without booting it. Gamend Cloud
reads a server's after each build, where it asked the running server over
`bin/<release> rpc`.
- [Gamend.Results](Gamend.Results.md): What happened in a play (priv/docs/40-gameplay/45-results.md).
- [Gamend.Results.Event](Gamend.Results.Event.md): Ecto schema for `result_events`: one thing that happened in a play
(`Gamend.Results.record/4`).
- [Gamend.Results.Result](Gamend.Results.Result.md): Ecto schema for `results`: one play by one player (`Gamend.Results`).
- [Gamend.Results.ResultStatus](Gamend.Results.ResultStatus.md): The states of a play's result.

- [Gamend.Results.ResultVisibility](Gamend.Results.ResultVisibility.md): Who can read a play's result.

- [Gamend.Secrets](Gamend.Secrets.md): Somewhere to keep a credential that belongs to a *customer*.
- [Gamend.Secrets.Secret](Gamend.Secrets.Secret.md): One encrypted value, and the metadata a person needs to manage something
they can never read back.
- [Gamend.Signaling](Gamend.Signaling.md): WebRTC signaling: who is in a room, and relaying offers between them.
- [Gamend.Signals](Gamend.Signals.md): Server-side signals: a plugin emits a named event, another part of the plugin
waits for it.
- [Gamend.Slug](Gamend.Slug.md): A name that is also its URL, unique per account: a group's
(`Gamend.Groups`, `<owner>/<slug>`), and in a host a project's or a store
account's (Forge's `/projects/<owner>/<name>`).
- [Gamend.SortDirection](Gamend.SortDirection.md): The direction of a sorted list.

- [Gamend.SortKey](Gamend.SortKey.md): The sort orders of the admin lists of rooms, shared across lobbies, groups, parties and chat.

- [Gamend.TestSupport.Race](Gamend.TestSupport.Race.md): Releases racers at the same instant, each on its own database connection,
so a test can show whether a rule holds when requests land together.
- [Gamend.Time](Gamend.Time.md): The server's wall clock, in milliseconds since the epoch, for sending to
clients.
- [Gamend.UrlScheme](Gamend.UrlScheme.md): URL schemes.

- Accounts
  - [Gamend.Accounts](Gamend.Accounts.md): The Accounts context.
  - [Gamend.Accounts.AgePolicy](Gamend.Accounts.AgePolicy.md): What a user's age permits.
  - [Gamend.Accounts.ApiToken](Gamend.Accounts.ApiToken.md): A personal API token's row. The token itself is never stored.
  - [Gamend.Accounts.ApiTokens](Gamend.Accounts.ApiTokens.md): Personal API tokens: long-lived bearer tokens for scripts and CI.
  - [Gamend.Accounts.AvatarMirror](Gamend.Accounts.AvatarMirror.md): Oban worker that mirrors a user's external (OAuth provider) avatar into our
own object storage, so avatars render from our storage/CDN instead of
hotlinking the provider.
  - [Gamend.Accounts.Broadcasts](Gamend.Accounts.Broadcasts.md): Telling connected clients a user changed: the `user:<id>` topic, and the
member and friend topics that show that user to others.
  - [Gamend.Accounts.ConfirmationMailer](Gamend.Accounts.ConfirmationMailer.md): Sends a new account's confirmation email, off the request.
  - [Gamend.Accounts.GuestMerge](Gamend.Accounts.GuestMerge.md): A guest's progress joins the account they log in to.
  - [Gamend.Accounts.Identities](Gamend.Accounts.Identities.md): How a person signs in without a password — Discord, Apple, Google, Facebook,
GitHub, Steam or a device id — and linking those identities to an existing account or
removing them from one.
  - [Gamend.Accounts.InactivityNotifier](Gamend.Accounts.InactivityNotifier.md): Warns a user their account is about to be deleted for inactivity.
  - [Gamend.Accounts.IntervalUnit](Gamend.Accounts.IntervalUnit.md): The unit of the age limits on account tokens, as SQL's `ago/2` reads it.

  - [Gamend.Accounts.LoginLockout](Gamend.Accounts.LoginLockout.md): Failed password sign-ins for one email address, and the lock they set.
  - [Gamend.Accounts.LoginLockouts](Gamend.Accounts.LoginLockouts.md): Per-account lockout after repeated failed password sign-ins.
  - [Gamend.Accounts.Online](Gamend.Accounts.Online.md): A player online, one way for every client. The SDK's game socket
(`GamendWeb.UserChannel`) and a host's own page (a LiveView the player
plays in) call the same functions, so `users.is_online`, friends' online
dots, lobby, party and group presence, matchmaking's offline prune and the
abandoned-lobby reaper see them alike.
  - [Gamend.Accounts.PasswordHash](Gamend.Accounts.PasswordHash.md): Password hashing: Argon2id for new hashes, bcrypt still accepted for old ones.
  - [Gamend.Accounts.Preferences](Gamend.Accounts.Preferences.md): A user's private settings (`users.preferences`): what only they see and
change — notification choices (`Gamend.Notifications.Preferences`), their
time zone (`Gamend.Accounts.TimeZone`) and the site language they last used
(`locale/1`, for email written to them).
  - [Gamend.Accounts.Presence](Gamend.Accounts.Presence.md): Whether a user is online, and when they were last seen.
  - [Gamend.Accounts.PresenceStatus](Gamend.Accounts.PresenceStatus.md): How recently a user was seen, as the three states the UI actually draws.
  - [Gamend.Accounts.PresenceWriter](Gamend.Accounts.PresenceWriter.md): Coalesces `users.is_online` transitions into one write per flush window.
  - [Gamend.Accounts.Profile](Gamend.Accounts.Profile.md): Changing what a user shows the world: display name, username, avatar, age and
metadata, and the storage that goes with them.
  - [Gamend.Accounts.Registration](Gamend.Accounts.Registration.md): Creating an account and confirming it: registration, the generated username,
the first-user-is-admin rule and account activation, and email confirmation.
  - [Gamend.Accounts.Scope](Gamend.Accounts.Scope.md): Defines the scope of the caller to be used throughout the app.
  - [Gamend.Accounts.Search](Gamend.Accounts.Search.md): Finding users: the player-facing search and the admin user listing.
  - [Gamend.Accounts.Sessions](Gamend.Accounts.Sessions.md): Signing in and staying signed in: session and magic-link tokens, the emails
that carry them, and listing or revoking a user's sessions.
  - [Gamend.Accounts.StalePresenceSweeper](Gamend.Accounts.StalePresenceSweeper.md): Periodically sweeps users whose `is_online` flag is `true` but whose
`last_seen_at` timestamp is older than a configurable threshold.
  - [Gamend.Accounts.Stats](Gamend.Accounts.Stats.md): Counts over the user table for the admin dashboard and the public stats page.
  - [Gamend.Accounts.ThemeName](Gamend.Accounts.ThemeName.md): A user's theme preference.

  - [Gamend.Accounts.TimeZone](Gamend.Accounts.TimeZone.md): A user's time zone, for "their day" and "their evening": an IANA name
(`"Europe/Bucharest"`) kept in their private preferences
(`Gamend.Accounts.Preferences`), taken from the browser
(`Intl.DateTimeFormat().resolvedOptions().timeZone`, sent on connect) or
chosen in settings. A zone chosen by hand (`choose/2`) stays until the user
goes back to automatic: the browser no longer overwrites it
(`manual?/1`). Unknown or unset, everything falls back to UTC.
  - [Gamend.Accounts.TokenContext](Gamend.Accounts.TokenContext.md): The `user_tokens.context` values that name what a token is for.

  - [Gamend.Accounts.User](Gamend.Accounts.User.md): The User schema and associated changeset functions used across the
application (registration, OAuth, and admin changes).
  - [Gamend.Accounts.UserNotifier](Gamend.Accounts.UserNotifier.md): Small helpers used to deliver transactional emails for the Accounts flow
(confirmation, magic link, and email change instructions).
  - [Gamend.Accounts.UserToken](Gamend.Accounts.UserToken.md): Functions and schema for persistent user tokens used by sessions, magic links,
email confirmation (a link and a code) and email-change workflows.
  - [Gamend.Accounts.Username](Gamend.Accounts.Username.md): The username handle's rules, in one place for the changeset and the
generator.
  - [Gamend.Accounts.UsernameGenerator](Gamend.Accounts.UsernameGenerator.md): Generates default usernames for new users.
  - [Gamend.Apple](Gamend.Apple.md): Apple OAuth client secret generation for Ueberauth.
  - [Gamend.OAuth.AuthProvider](Gamend.OAuth.AuthProvider.md): The OAuth providers a player signs in with.

  - [Gamend.OAuth.Exchanger](Gamend.OAuth.Exchanger.md): Default implementation for exchanging OAuth codes with providers.
  - [Gamend.OAuth.GoogleIDToken](Gamend.OAuth.GoogleIDToken.md): Verifies Google OpenID Connect `id_token`s for native/mobile sign-in flows.
  - [Gamend.OAuth.Providers](Gamend.OAuth.Providers.md): Credentials and availability for the social sign-in providers.
  - [Gamend.OAuth.SessionStatus](Gamend.OAuth.SessionStatus.md): The states of a provider sign-in in progress.

  - [Gamend.OAuthSession](Gamend.OAuthSession.md): Simple Ecto schema for OAuth session polling used by client SDKs.
  - [Gamend.OAuthSessions](Gamend.OAuthSessions.md): Helpers for creating and retrieving short-lived OAuth sessions.

- Lobbies
  - [Gamend.Lobbies](Gamend.Lobbies.md): Context module for lobby management: creating, updating, listing and searching lobbies.
  - [Gamend.Lobbies.Lobby](Gamend.Lobbies.Lobby.md): Ecto schema for the `lobbies` table and changeset helpers.
  - [Gamend.Lobbies.LobbyState](Gamend.Lobbies.LobbyState.md): A lobby's initial state.

  - [Gamend.Lobbies.SpectatorTracker](Gamend.Lobbies.SpectatorTracker.md): Who is watching a lobby without being a member.
  - [Gamend.Lobbies.States](Gamend.Lobbies.States.md): The vocabulary a lobby's `state` commonly uses.

- Matchmaking
  - [Gamend.Matchmaking](Gamend.Matchmaking.md): Public API for the built-in matchmaking system.
  - [Gamend.Matchmaking.Broadcast](Gamend.Matchmaking.Broadcast.md): Broadcasts matchmaking events to users: a ticket queued, cancelled, or
matched into a lobby.
  - [Gamend.Matchmaking.CancelReason](Gamend.Matchmaking.CancelReason.md): Why a matchmaking ticket was cancelled, as broadcast to the player.

  - [Gamend.Matchmaking.Constants](Gamend.Matchmaking.Constants.md): Constants for the matchmaking system.

  - [Gamend.Matchmaking.Match](Gamend.Matchmaking.Match.md): Creates the lobby for a claimed match and notifies the players.
  - [Gamend.Matchmaking.Matcher](Gamend.Matchmaking.Matcher.md): Match-forming logic for a group of tickets that share the same
`match_params`.
  - [Gamend.Matchmaking.Ticket](Gamend.Matchmaking.Ticket.md): Ecto schema for a matchmaking ticket.
  - [Gamend.Matchmaking.TicketStatus](Gamend.Matchmaking.TicketStatus.md): The states of a matchmaking ticket.

  - [Gamend.Matchmaking.Worker](Gamend.Matchmaking.Worker.md): Periodic driver for the matchmaking sweep.
  - [Gamend.ReadyChecks](Gamend.ReadyChecks.md): Ready checks: *these players must each answer before this proceeds*.
  - [Gamend.ReadyChecks.Check](Gamend.ReadyChecks.Check.md): Ecto schema for one ready check — a *moment* at which a set of players must
each answer before something proceeds.
  - [Gamend.ReadyChecks.CheckKind](Gamend.ReadyChecks.CheckKind.md): Which question a ready check asks.

  - [Gamend.ReadyChecks.CheckReason](Gamend.ReadyChecks.CheckReason.md): Why a ready check ended without passing.

  - [Gamend.ReadyChecks.CheckScope](Gamend.ReadyChecks.CheckScope.md): What a ready check runs on.

  - [Gamend.ReadyChecks.CheckStatus](Gamend.ReadyChecks.CheckStatus.md): The states of a ready check: `ready_checks.status`.

  - [Gamend.ReadyChecks.Participant](Gamend.ReadyChecks.Participant.md): Ecto schema for one player's answer inside a ready check.
  - [Gamend.ReadyChecks.ParticipantState](Gamend.ReadyChecks.ParticipantState.md): A participant's answer to a ready check.

- Social
  - [Gamend.Chat](Gamend.Chat.md): Context for chat messaging across lobbies, groups, and friend DMs.
  - [Gamend.Chat.ChatReportStatus](Gamend.Chat.ChatReportStatus.md): The states of a report about a chat message.

  - [Gamend.Chat.ChatType](Gamend.Chat.ChatType.md): The kinds of conversation.

  - [Gamend.Chat.FilterSeverity](Gamend.Chat.FilterSeverity.md): What the word filter does with a match.

  - [Gamend.Chat.FilterWord](Gamend.Chat.FilterWord.md): Ecto schema for the `chat_filter_words` table — one entry of the chat word
blocklist.
  - [Gamend.Chat.MatchMode](Gamend.Chat.MatchMode.md): How the word filter matches a word.

  - [Gamend.Chat.Message](Gamend.Chat.Message.md): Ecto schema for the `chat_messages` table.
  - [Gamend.Chat.Moderation](Gamend.Chat.Moderation.md): Chat word filter and mutes.
  - [Gamend.Chat.Moderation.Cache](Gamend.Chat.Moderation.Cache.md): Node-local hot path for chat moderation's word blocklist. (Mutes are chat
bans, cached by `Gamend.Bans.Cache`.)
  - [Gamend.Chat.Moderation.Normalizer](Gamend.Chat.Moderation.Normalizer.md): Canonical form for chat filter matching.
  - [Gamend.Chat.Moderation.Notices](Gamend.Chat.Moderation.Notices.md): The notifications chat moderation sends: alerting admins that a report landed,
warning a player, telling a player they were muted, and telling a reporter
what came of their report.
  - [Gamend.Chat.Moderation.Sync](Gamend.Chat.Moderation.Sync.md): Keeps the node-local word blocklist (`Gamend.Chat.Moderation.Cache`) in sync
with the database and the other app instances. Mutes are chat bans, kept in
step by `Gamend.Bans.Sync`.
  - [Gamend.Chat.ReadCursor](Gamend.Chat.ReadCursor.md): Ecto schema for the `chat_read_cursors` table.
  - [Gamend.Chat.Report](Gamend.Chat.Report.md): Ecto schema for the `chat_reports` table — a player- or filter-filed report
about a chat message.
  - [Gamend.Chat.Reports](Gamend.Chat.Reports.md): The chat report queue.
  - [Gamend.Friends](Gamend.Friends.md): Friends context - handles friend requests and relationships.
  - [Gamend.Friends.Friendship](Gamend.Friends.Friendship.md): Ecto schema representing a friendship/request between two users.
  - [Gamend.Friends.FriendshipStatus](Gamend.Friends.FriendshipStatus.md): The states of a friendship row.

  - [Gamend.Groups](Gamend.Groups.md): Context module for group management: creating, updating, listing, joining,
leaving, kicking, promoting/demoting members, and handling join requests.
  - [Gamend.Groups.Group](Gamend.Groups.Group.md): Ecto schema for the `groups` table.
  - [Gamend.Groups.GroupInvite](Gamend.Groups.GroupInvite.md): Ecto schema for the `group_invites` table.
  - [Gamend.Groups.GroupInviteLink](Gamend.Groups.GroupInviteLink.md): Ecto schema for the `group_invite_links` table: a group's invite link
(`Gamend.Groups.InviteLinks`).
  - [Gamend.Groups.GroupInviteStatus](Gamend.Groups.GroupInviteStatus.md): The states of an invitation to a group.

  - [Gamend.Groups.GroupJoinRequest](Gamend.Groups.GroupJoinRequest.md): Ecto schema for the `group_join_requests` table.
  - [Gamend.Groups.GroupMember](Gamend.Groups.GroupMember.md): Ecto schema for the `group_members` join table.
  - [Gamend.Groups.GroupRole](Gamend.Groups.GroupRole.md): A member's role in a group: `group_members.role`.

  - [Gamend.Groups.GroupType](Gamend.Groups.GroupType.md): Who can find and join a group: `groups.type`.

  - [Gamend.Groups.InviteLinks](Gamend.Groups.InviteLinks.md): A group's invite link: an admin makes one, shares it anywhere, and whoever
opens it while signed in joins the group as a member, without an invite of
their own or a request to approve. It works for every group type, hidden
ones too, and is a pull, like a class code: the person chooses to join,
nobody is added to anything.
  - [Gamend.Groups.Invites](Gamend.Groups.Invites.md): Group invitations: creating, accepting, declining, cancelling, and
listing/counting pending invites.
  - [Gamend.Groups.JoinOutcome](Gamend.Groups.JoinOutcome.md): What a join request became: `POST /groups/:id/join`.

  - [Gamend.Groups.JoinRequestStatus](Gamend.Groups.JoinRequestStatus.md): The states of a request to join a group.

  - [Gamend.Groups.JoinRequests](Gamend.Groups.JoinRequests.md): Join requests for private groups: requesting, listing, approving,
rejecting, and cancelling.
  - [Gamend.Parties](Gamend.Parties.md): Context module for party management.
  - [Gamend.Parties.Party](Gamend.Parties.Party.md): Ecto schema for the `parties` table.
  - [Gamend.Parties.PartyInvite](Gamend.Parties.PartyInvite.md): Ecto schema for the `party_invites` table.
  - [Gamend.Parties.PartyInviteStatus](Gamend.Parties.PartyInviteStatus.md): The states of an invitation to a party.

- Progression
  - [Gamend.Leaderboards](Gamend.Leaderboards.md): The Leaderboards context.
  - [Gamend.Leaderboards.Leaderboard](Gamend.Leaderboards.Leaderboard.md): Ecto schema for the `leaderboards` table.
  - [Gamend.Leaderboards.Record](Gamend.Leaderboards.Record.md): Ecto schema for the `leaderboard_records` table.
  - [Gamend.Leaderboards.ScoreOperator](Gamend.Leaderboards.ScoreOperator.md): How a leaderboard's records combine a new score.

  - [Gamend.Quests](Gamend.Quests.md): Event-driven quest/progression engine.
  - [Gamend.Quests.Codes](Gamend.Quests.Codes.md): Redemption codes: making them, finding them, stopping them.
  - [Gamend.Quests.Objective](Gamend.Quests.Objective.md): One objective inside a quest definition: reach `target` occurrences of
`event` (as reported through `Gamend.Quests.report_event/4`).
  - [Gamend.Quests.PeriodKey](Gamend.Quests.PeriodKey.md): The period key of a quest that never resets.

  - [Gamend.Quests.Quest](Gamend.Quests.Quest.md): Ecto schema for the `quests` table.
  - [Gamend.Quests.QuestCategory](Gamend.Quests.QuestCategory.md): A quest category with a meaning of its own.

  - [Gamend.Quests.QuestCode](Gamend.Quests.QuestCode.md): Ecto schema for the `quest_codes` table: one redemption code of a
`code_only` quest (`Gamend.Quests.redeem_code/2`).
  - [Gamend.Quests.QuestCodeStatus](Gamend.Quests.QuestCodeStatus.md): Whether a redemption code still works: `quest_codes.status`.

  - [Gamend.Quests.QuestFilter](Gamend.Quests.QuestFilter.md): The status filters of a quest list (not stored values).

  - [Gamend.Quests.QuestProgress](Gamend.Quests.QuestProgress.md): Ecto schema for the `quest_progress` table — one row per user, quest and
reset period.
  - [Gamend.Quests.QuestReset](Gamend.Quests.QuestReset.md): How often a quest resets.

  - [Gamend.Quests.QuestStatus](Gamend.Quests.QuestStatus.md): A player's progress on a quest: `quest_progress.status`.

  - [Gamend.Quests.ReportedEvent](Gamend.Quests.ReportedEvent.md): An event core reports to the quests of a player.

  - [Gamend.Quests.Reward](Gamend.Quests.Reward.md): One reward entry on a quest definition: `amount` of a currency
(via `Gamend.Economy.grant/4`) or an item
(via `Gamend.Inventory.grant_item/4`).

  - [Gamend.Quests.RewardType](Gamend.Quests.RewardType.md): What a quest's reward grants.

  - [Gamend.Tournaments](Gamend.Tournaments.md): Bracket tournaments: registration → seeded single-elimination draw → timed
rounds → champions. See TOURNAMENT_DESIGN.md.
  - [Gamend.Tournaments.DeadlinePolicy](Gamend.Tournaments.DeadlinePolicy.md): What happens to a match past its deadline.

  - [Gamend.Tournaments.Entry](Gamend.Tournaments.Entry.md): One side of the bracket: a leader and their tournament progress.
  - [Gamend.Tournaments.EntryState](Gamend.Tournaments.EntryState.md): A participant's state in a tournament.

  - [Gamend.Tournaments.Match](Gamend.Tournaments.Match.md): A pairing plus a verdict: two entries that must produce a winner by
`deadline_at`. Never a lobby — how the pairing is played is game policy;
`metadata` is game scratch space (runs, lobby id, ...).

  - [Gamend.Tournaments.Ticker](Gamend.Tournaments.Ticker.md): Periodic driver for tournament lifecycles: state transitions, match-ready
firing, deadline_at sweeps and recurrence spawns (`Gamend.Tournaments.tick/0`).
  - [Gamend.Tournaments.Tournament](Gamend.Tournaments.Tournament.md): A bracket tournament occurrence.
  - [Gamend.Tournaments.TournamentState](Gamend.Tournaments.TournamentState.md): The states of a tournament.

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
  - [Gamend.Payments.Admin](Gamend.Payments.Admin.md): What the admin payments pages and API read: the stats, provider configuration
status, and filtered listings of products, purchases, entitlements, provider
events and reconciliation cursors.
  - [Gamend.Payments.CounterName](Gamend.Payments.CounterName.md): The counters of payments in `Gamend.Payments.Counters`.

  - [Gamend.Payments.Counters](Gamend.Payments.Counters.md): What happened to payments, per day, as `Gamend.Analytics.count/3` counters:
the admin analytics page lists them under "Counters" with the game's own.
  - [Gamend.Payments.DeletedAccountSubscriptions](Gamend.Payments.DeletedAccountSubscriptions.md): A deleted account stops being charged.
  - [Gamend.Payments.Entitlement](Gamend.Payments.Entitlement.md): User access grant derived from a purchase or admin/server action.

  - [Gamend.Payments.EntitlementStatus](Gamend.Payments.EntitlementStatus.md): The states of an entitlement.

  - [Gamend.Payments.GrantKey](Gamend.Payments.GrantKey.md): Keys of a product's grant config that core and the store read.

  - [Gamend.Payments.Notices](Gamend.Payments.Notices.md): Telling a user about an entitlement given to them on purpose: a trial
lengthened by support, a reward. Only when the grant asks for it (`notify:
true` on `Gamend.Payments.grant_entitlement/3` or `extend_entitlement/3`, the
"Tell user" box on Admin > Payments).
  - [Gamend.Payments.Params](Gamend.Payments.Params.md): Shape-wrangling shared by `Gamend.Payments` and its provider adapters.
  - [Gamend.Payments.PaymentEnvironment](Gamend.Payments.PaymentEnvironment.md): Where a purchase was made: `purchases.environment`.

  - [Gamend.Payments.Product](Gamend.Payments.Product.md): Internal product sold by one or more payment providers.

  - [Gamend.Payments.ProductKind](Gamend.Payments.ProductKind.md): What a product grants.

  - [Gamend.Payments.Provider](Gamend.Payments.Provider.md): Behaviour for a store adapter — Apple, Google, Steam, or a host's own.
  - [Gamend.Payments.ProviderConfig](Gamend.Payments.ProviderConfig.md): Runtime payment-provider configuration helpers.
  - [Gamend.Payments.ProviderErrorCode](Gamend.Payments.ProviderErrorCode.md): The code of a provider failure that was our own input's fault.

  - [Gamend.Payments.ProviderEvent](Gamend.Payments.ProviderEvent.md): Dedupe record for webhook and store notification events.

  - [Gamend.Payments.ProviderId](Gamend.Payments.ProviderId.md): The payment providers core knows, as stored in `purchases.provider`.

  - [Gamend.Payments.ProviderProduct](Gamend.Payments.ProviderProduct.md): Maps an internal product to a provider-specific SKU or price id.

  - [Gamend.Payments.Providers.Apple](Gamend.Payments.Providers.Apple.md): App Store Server API and StoreKit 2 adapter.
  - [Gamend.Payments.Providers.Apple.JWS](Gamend.Payments.Providers.Apple.JWS.md): Verifies App Store JWS payloads (StoreKit signed transactions and App Store
Server Notifications V2).
  - [Gamend.Payments.Providers.Google](Gamend.Payments.Providers.Google.md): Google Play Billing adapter.
  - [Gamend.Payments.Providers.Steam](Gamend.Payments.Providers.Steam.md): Steam MicroTxn adapter.
  - [Gamend.Payments.Providers.Stripe](Gamend.Payments.Providers.Stripe.md): Minimal Stripe Checkout and webhook adapter.

  - [Gamend.Payments.Purchase](Gamend.Payments.Purchase.md): Provider transaction record.

  - [Gamend.Payments.PurchaseMetadata](Gamend.Payments.PurchaseMetadata.md): Keys payments keeps in a purchase's metadata.

  - [Gamend.Payments.PurchaseStatus](Gamend.Payments.PurchaseStatus.md): The states of a purchase: `purchases.status`.

  - [Gamend.Payments.ReconciliationCursor](Gamend.Payments.ReconciliationCursor.md): Provider reconciliation checkpoint.

  - [Gamend.Payments.Settings](Gamend.Payments.Settings.md): Store credentials, per provider.
  - [Gamend.Payments.StoreEvents](Gamend.Payments.StoreEvents.md): Apple App Store and Google Play server notifications: verifying them, recording
them once, and applying what they say to purchases and entitlements.
  - [Gamend.Payments.StripeEvent](Gamend.Payments.StripeEvent.md): A Stripe webhook's event name.

  - [Gamend.Payments.StripeEvents](Gamend.Payments.StripeEvents.md): Stripe: starting a checkout, and keeping purchases and entitlements in step
with what Stripe says — webhooks as they arrive, reconciliation when one was
missed, and cancelling a subscription at the end of its period.
  - [Gamend.Payments.StripeIdPrefix](Gamend.Payments.StripeIdPrefix.md): The prefixes of Stripe ids and keys.

  - [Gamend.Payments.StripeKeyMode](Gamend.Payments.StripeKeyMode.md): What a Stripe API key is for, read from its prefix.

  - [Gamend.Payments.StripeMode](Gamend.Payments.StripeMode.md): A Stripe Checkout session's `mode`.

  - [Gamend.Payments.StripePlanChange](Gamend.Payments.StripePlanChange.md): Moving a running Stripe subscription to another product of the same period:
a hosted server's size, a tier of a monthly plan. Not a longer plan
(monthly to yearly), which is a new checkout (`Gamend.Payments.Upgrades`).
  - [Gamend.Payments.StripeRefunds](Gamend.Payments.StripeRefunds.md): Refunding a Stripe purchase in full: the buyer's own, within
`refund_window_days` of paying (account settings, Payments), or any Stripe
purchase from the admin page.
  - [Gamend.Payments.StripeSetup](Gamend.Payments.StripeSetup.md): The Stripe account set up the way this code reads it, from a script
(`mix gamend.stripe.setup`, a host's own task for its prices), never by
hand-copying a checklist
  - [Gamend.Payments.StripeSetupStep](Gamend.Payments.StripeSetupStep.md): The steps of `mix gamend.stripe.setup`.

  - [Gamend.Payments.StripeStatus](Gamend.Payments.StripeStatus.md): Stripe's own statuses, read off its objects (not the rows it updates).

  - [Gamend.Payments.StripeSweeper](Gamend.Payments.StripeSweeper.md): The safety net for a Stripe webhook that never arrived.
  - [Gamend.Payments.Upgrades](Gamend.Payments.Upgrades.md): Moving to a longer plan: a monthly subscription to a yearly one, or any
subscription to a one-off purchase (lifetime) of the same entitlement.
Never for a per-subject product (`Payments.per_subject?/1`): each subject's
purchase stands alone.

- Storage &amp; content
  - [Gamend.Content](Gamend.Content.md): Reads and renders Markdown content from project files and directories.
  - [Gamend.Content.Frontmatter](Gamend.Content.Frontmatter.md): The `---` block at the top of a markdown file.
  - [Gamend.Content.Markdown](Gamend.Content.Markdown.md): Markdown to HTML, the way every collection renders it.
  - [Gamend.Content.Offline](Gamend.Content.Offline.md): A guide collection as one HTML file that needs no server.
  - [Gamend.Content.PageName](Gamend.Content.PageName.md): The page a folder of content opens on.

  - [Gamend.Content.Tree](Gamend.Content.Tree.md): A guide collection read as a tree: folders are categories, at any depth.
  - [Gamend.ContentSettings](Gamend.ContentSettings.md): Where the server finds host-supplied content: the theme config, hook plugins,
project static files, and the GeoIP database.

  - [Gamend.KV](Gamend.KV.md): Generic key/value storage.
  - [Gamend.Settings](Gamend.Settings.md): The declared configuration surface: every setting core, the host and its
plugins expose, with its type, default, group, env var name and required
level.
  - [Gamend.Settings.Provider](Gamend.Settings.Provider.md): Declares a group of settings on a module.
  - [Gamend.Storage](Gamend.Storage.md): Object storage for user uploads (avatars, and future user-generated content).
  - [Gamend.Storage.Adapter](Gamend.Storage.Adapter.md): Behaviour for object-storage backends.
  - [Gamend.Storage.Local](Gamend.Storage.Local.md): Disk-backed storage — the default backend.
  - [Gamend.Storage.S3](Gamend.Storage.S3.md): S3-compatible storage via ExAws.
  - [Gamend.Storage.StoragePrefix](Gamend.Storage.StoragePrefix.md): The first segment of an object's key.

  - [Gamend.Theme](Gamend.Theme.md): Behaviour for pluggable site theming providers.
  - [Gamend.Theme.JSONConfig](Gamend.Theme.JSONConfig.md): JSON-backed Theme provider. Reads **one** config file — from the
`GAMEND_CONTENT_THEME_CONFIG` setting or the host-owned default path — and
translates its text through gettext at read time.
  - [Gamend.Theme.Translatable](Gamend.Theme.Translatable.md): Which leaves of a theme config are text, and which are configuration.

- Delivery
  - [Gamend.Notifications](Gamend.Notifications.md): Notifications context – create, list, and delete persisted user-to-user
notifications.
  - [Gamend.Notifications.Digest](Gamend.Notifications.Digest.md): Emails that wait and go out together: a group with `email_every`
(`Gamend.Notifications.Preferences`) keeps its notices here, and one email
lists them.
  - [Gamend.Notifications.DigestItem](Gamend.Notifications.DigestItem.md): One notice waiting for a digest email (`Gamend.Notifications.Digest`).
  - [Gamend.Notifications.DigestSweeper](Gamend.Notifications.DigestSweeper.md): Hourly, queues the digest emails that are due
(`Gamend.Notifications.Digest.sweep/1`). `enabled: false` in the app config
keeps it supervised but idle, for test suites. Safe on several nodes at
once: the job is unique per user and group.

  - [Gamend.Notifications.Notification](Gamend.Notifications.Notification.md): Ecto schema representing a notification sent from one user to another.
  - [Gamend.Notifications.NotificationChannel](Gamend.Notifications.NotificationChannel.md): The channels a notification can be sent on.

  - [Gamend.Notifications.NotificationType](Gamend.Notifications.NotificationType.md): The `metadata["type"]` codes core writes on a notification. The registry with their descriptions is `Gamend.Notifications.Types`.

  - [Gamend.Notifications.PreferenceGroup](Gamend.Notifications.PreferenceGroup.md): The groups a player's notification choices are made per.

  - [Gamend.Notifications.PreferenceSwitch](Gamend.Notifications.PreferenceSwitch.md): The switches that turn a channel off for every group.

  - [Gamend.Notifications.Preferences](Gamend.Notifications.Preferences.md): Which notifications a user wants, and how: per GROUP (a row on the
settings page: "Friends and groups", a host's "Streak about to end") and
per CHANNEL (`in_app`, `email`, `push`), plus three switches that win over
everything: all email off, all push off, everything off.
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
  - [Gamend.Push.Platform](Gamend.Push.Platform.md): What a push token was registered from.

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

  - [Gamend.Push.PushProvider](Gamend.Push.PushProvider.md): Who delivers a push token's notifications.

  - [Gamend.Push.PushToken](Gamend.Push.PushToken.md): Ecto schema for a registered device push token.
  - [Gamend.Push.Supervisor](Gamend.Push.Supervisor.md): Supervises the push delivery processes: the Goth worker (FCM OAuth) and the
two Pigeon dispatchers.
  - [Gamend.Push.TokenFilter](Gamend.Push.TokenFilter.md): The status filters of the push tokens list.

  - [Gamend.Realtime](Gamend.Realtime.md): Pushing game-defined realtime events to a player's socket.
  - [Gamend.Realtime.RealtimeEvent](Gamend.Realtime.RealtimeEvent.md): The names of the server-to-client channel events core and the channels both spell. The registry that lists them with their payloads is `GamendWeb.RealtimeEvents`.

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
  - [Gamend.Hooks.PluginBuilder](Gamend.Hooks.PluginBuilder.md): Builds an OTP plugin bundle (`ebin/*.beam` + `ebin/<app>.app`) from plugin
source code on disk, for the admin Config page and the command line.
  - [Gamend.Hooks.PluginBuilder.InProcess](Gamend.Hooks.PluginBuilder.InProcess.md): Builds a plugin bundle inside the running VM, without Mix.
  - [Gamend.Hooks.PluginBuilder.Project](Gamend.Hooks.PluginBuilder.Project.md): What a plugin's `mix.exs` declares, read without evaluating it.
  - [Gamend.Hooks.PluginFile](Gamend.Hooks.PluginFile.md): The files and folders of a built plugin.

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
  - [Gamend.Jobs](Gamend.Jobs.md): Durable background jobs, backed by Oban.
  - [Gamend.Limits](Gamend.Limits.md): Central module for configurable validation limits.
  - [Gamend.Lock](Gamend.Lock.md): Serialized execution using database-level advisory locks.
  - [Gamend.Lock.Local](Gamend.Lock.Local.md): Reentrant keyed mutex, first come first served: the non-Postgres half of
`Gamend.Lock.serialize/3`, and the node-local line in front of the Postgres
advisory lock.
  - [Gamend.Lock.Queue](Gamend.Lock.Queue.md): The waiting line behind `Gamend.Lock.Local`: per key, one holder and the
callers after it, served in the order they asked.
  - [Gamend.Mailer](Gamend.Mailer.md)
  - [Gamend.Repo](Gamend.Repo.md)
  - [Gamend.Repo.AdvisoryLock](Gamend.Repo.AdvisoryLock.md): Advisory locking for protecting TOCTOU (Time-of-Check-Time-of-Use) patterns.
  - [Gamend.Repo.MigrationPaths](Gamend.Repo.MigrationPaths.md): Resolves every migration directory that belongs to a gamend deployment.
  - [Gamend.Repo.SlowLog](Gamend.Repo.SlowLog.md): Names what is slow in the database, in the log.
  - [Gamend.Reports](Gamend.Reports.md): Reports about the game itself: a page that broke, a word that is wrong, an
image that does not match. Filed from `/report` or `POST /api/v1/reports`,
with or without an account, and worked from `/admin/reports`.
  - [Gamend.Reports.Kind](Gamend.Reports.Kind.md): What a report can be about.
  - [Gamend.Reports.Kinds.Page](Gamend.Reports.Kinds.Page.md): The built-in report kind: something on a page is broken or looks wrong.
  - [Gamend.Reports.Notices](Gamend.Reports.Notices.md): The notifications reports send: one standing "N reports waiting" alert per
admin, and a reply to a reporter who had an account.
  - [Gamend.Reports.Report](Gamend.Reports.Report.md): Ecto schema for the `reports` table: one report a player filed about the
game — a page, a word, anything a `Gamend.Reports.Kind` describes.
  - [Gamend.Reports.ReportSource](Gamend.Reports.ReportSource.md): Where a report was filed from.

  - [Gamend.Reports.ReportStatus](Gamend.Reports.ReportStatus.md): A report's status before anyone answers it. The other statuses come from the kind.

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
  - [Gamend.UUIDv7](Gamend.UUIDv7.md): The id of every row: a UUIDv7 (RFC 9562), made by `Ecto.UUID`.

## Mix Tasks

- [mix demo.seed](Mix.Tasks.Demo.Seed.md): Fills the database with demo data. See `Gamend.DemoSeed` for the sets and
options; a release runs the same code as `gamend demo.seed`.
- [mix gamend.api.lint](Mix.Tasks.Gamend.Api.Lint.md): Enforces the naming and serialization conventions mechanically.
- [mix gamend.content.extract](Mix.Tasks.Gamend.Content.Extract.md): Writes `content.pot` from the titles and descriptions stored on quests,
leaderboards and tournaments, and the names a quest gives its item rewards
(`metadata["reward_names"]`).
- [mix gamend.content.migrate_metadata](Mix.Tasks.Gamend.Content.MigrateMetadata.md): One-shot migration for instances that stored translations in the database.
- [mix gamend.gen.dockerfile](Mix.Tasks.Gamend.Gen.Dockerfile.md): Writes `Dockerfile` from Gamend's one template, filled in from the app's
own `mix.exs`, so Gamend, the starter and every host build the same way.
- [mix gamend.latest](Mix.Tasks.Gamend.Latest.md): Sets `@gamend_min` in the app's `mix.exs` to Gamend's newest release on Hex.
- [mix gamend.literal.lint](Mix.Tasks.Gamend.Literal.Lint.md): Flags a string that is really a name (a status, an action, a kind) typed out
across modules. See `Gamend.LiteralLint` for what counts and for the
`# literal-ok: <reason>` marker that accepts one.
- [mix gamend.race.lint](Mix.Tasks.Gamend.Race.Lint.md): Flags functions that keep a rule with a write only an earlier read made
safe: a state column written on a struct, a count then an insert, a cached
read deciding a write. See `Gamend.RaceLint` for each check and for the
`# race-safe: <reason>` marker that accepts one.
- [mix gamend.settings.env_example](Mix.Tasks.Gamend.Settings.EnvExample.md): Writes `.env.example` from `Gamend.Settings.all/0`, grouped and
commented from each setting's declaration.
- [mix gamend.settings.guide](Mix.Tasks.Gamend.Settings.Guide.md): Writes the public Settings guide from `Gamend.Settings.all/0`.
- [mix gamend.stripe.setup](Mix.Tasks.Gamend.Stripe.Setup.md): The Stripe account's webhook endpoint and customer portal, as
`Gamend.Payments.StripeSetup` wants them, on the account the configured
secret key belongs to (`GAMEND_PAYMENTS_ENVIRONMENT` picks the sandbox or
the production key, read from `.env` like the server reads it).
- [mix gamend.theme.extract](Mix.Tasks.Gamend.Theme.Extract.md): Writes `theme.pot` from the strings in the theme config.
- [mix gamend.theme.migrate_locales](Mix.Tasks.Gamend.Theme.MigrateLocales.md): One-shot migration off one-JSON-file-per-locale.
- [mix gen.sdk](Mix.Tasks.Gen.Sdk.md): Generates SDK stub modules from the real Gamend modules.
- [mix host.proto.check](Mix.Tasks.Host.Proto.Check.md): Check that registered protobuf schemas actually match the JSON they encode.
- [mix host.proto.gen](Mix.Tasks.Host.Proto.Gen.md): Generates protobuf bindings for every target from a `.proto` file.

