---
icon: hero-adjustments-horizontal
generated: by `mix gamend.settings.guide` - do not edit by hand; edit the
  declaration in the module that owns the setting
---

# Settings

Every setting the server has, with the environment variable that sets it.
309 settings across 28 groups.

A setting is declared in the module that owns it, so this page and
`.env.example` are generated from the same source the server reads. The
variable name is derived from the declaration rather than written by hand.

Environment variables are one *input method*. A host can configure the
ordinary Elixir way instead, and everything ends at `Application` config:

```elixir
config :gamend_core, Gamend.Retention, chat_messages_days: 90
```

To feed the variables below in, a host's `config/runtime.exs` runs one loop
over `GamendWeb.HostRuntime.config/2`. It folds in
`Gamend.Settings.from_env/0` and also derives the Repo, Endpoint, mailer and
push configuration from these settings, so a loop over `from_env/0` alone
boots a production server with no Repo or Endpoint configuration:

```elixir
host_root = System.get_env("RELEASE_ROOT") || Path.expand("..", __DIR__)

for entry <- GamendWeb.HostRuntime.config(config_env(), host_root: host_root) do
  case entry do
    {app, opts} -> config app, opts
    {app, key, value} -> config app, key, value
  end
end
```

Live values, and where each one came from, are on the
[admin settings page](/admin/settings).


## Authentication

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_AUTH_ACCESS_TOKEN_TTL_MINUTES` | integer | `15` | Lifetime of API access tokens, in minutes. Login and refresh answer it as expires_in. Applies to tokens issued after the change. |
| `GAMEND_AUTH_ANONYMOUS_CAN_UPLOAD_AVATAR` | boolean | `false` | Allow device-only accounts to upload an avatar. Off by default: an anonymous account costs one request to create, so this is the cheapest way for a bot to burn object storage. |
| `GAMEND_AUTH_API_TOKEN_MAX_DAYS` | integer | `0` | Longest lifetime a personal API token may have, in days. Applies to existing tokens too, counted from creation. 0 allows tokens that never expire. |
| `GAMEND_AUTH_ARGON2_MEMORY_LOG2` | integer | `14` | Argon2id memory per hash, as a power of two in KiB — 14 is 16 MiB. Peak use is this times the vCPU count, not times the request rate, because the BEAM runs at most one hash per dirty CPU scheduler. Below 12 (4 MiB) it stops being meaningfully memory-hard. |
| `GAMEND_AUTH_ARGON2_TIME_COST` | integer | `3` | Argon2id passes over memory. Raise to compensate when lowering memory. |
| `GAMEND_AUTH_CHANGE_EMAIL_DAYS` | integer | `7` | How long the link confirming a new email address stays valid, in days. |
| `GAMEND_AUTH_CONFIRM_EMAIL_DAYS` | integer | `7` | How long an email confirmation link stays valid, in days. |
| `GAMEND_AUTH_DELETION_GRACE_DAYS` | integer | `0` | Days between a player deleting their own account and it being deleted. Signing in on the website within that time keeps the account. 0 deletes at once. |
| `GAMEND_AUTH_DEVICE_AUTH_ENABLED` | boolean | `true` | Allow POST /api/v1/login/device. When on, any unknown device_id creates an anonymous account. |
| `GAMEND_AUTH_GUARDIAN_SECRET_KEY` | string | - | JWT signing key. Defaults to secret_key_base when unset. Secret - never log or commit it. |
| `GAMEND_AUTH_LOCKOUT_ATTEMPTS` | integer | `10` | Failed passwords for one email address that lock its password sign-in. Counted per address across every IP. 0 disables the lockout. |
| `GAMEND_AUTH_LOCKOUT_MINUTES` | integer | `15` | How long a lock lasts. Emailed login links and provider sign-in still work meanwhile, so the owner is never shut out. |
| `GAMEND_AUTH_LOCKOUT_WINDOW_MINUTES` | integer | `15` | The failures must fall within this many minutes to lock. |
| `GAMEND_AUTH_MAGIC_LINK_MINUTES` | integer | `15` | How long an emailed login link stays valid, in minutes. Capped at 60: anyone who can read the email can sign in while the link lives. |
| `GAMEND_AUTH_MIN_PASSWORD_LENGTH` | integer | `8` | Minimum password length enforced at registration and change. |
| `GAMEND_AUTH_REFRESH_TOKEN_TTL_DAYS` | integer | `30` | Lifetime of API refresh tokens, in days. A refresh keeps its token, so this is how long a client stays signed in without logging in again. |
| `GAMEND_AUTH_REQUIRE_ACTIVATION` | boolean | `false` | New accounts cannot log in until an admin activates them (beta mode). |
| `GAMEND_AUTH_SECRET_KEY_BASE` | string | - | Signs and encrypts cookies, tokens and LiveView sessions. **Required in production.** Secret - never log or commit it. |
| `GAMEND_AUTH_SESSION_DAYS` | integer | `14` | Lifetime of a browser session and its remember-me cookie, in days. An active session is renewed once it is half this old. |
| `GAMEND_AUTH_SUDO_MODE_MINUTES` | integer | `10` | How recently a user must have signed in to open the settings that change their password or email. Submitting the form is allowed 10 minutes more. |


## Background jobs

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_JOBS_PRUNE_AFTER_DAYS` | integer | `7` | Days finished, cancelled and discarded jobs are kept before they are deleted. |
| `GAMEND_JOBS_QUEUE_DEFAULT` | integer | `10` | Per-node concurrent jobs on the default queue. |
| `GAMEND_JOBS_QUEUE_HOOKS` | integer | `20` | Per-node concurrent jobs on the hooks queue: enqueued and scheduled plugin hooks. |
| `GAMEND_JOBS_QUEUE_MAILERS` | integer | `5` | Per-node concurrent email sends. |
| `GAMEND_JOBS_QUEUE_STORAGE` | integer | `5` | Per-node concurrent storage jobs, such as avatar mirroring. |
| `GAMEND_JOBS_QUEUE_WEBHOOKS` | integer | `10` | Per-node concurrent outgoing webhook deliveries. |


## Cache

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_CACHE_ENABLED` | boolean | `true` | Set false to bypass caching entirely. |
| `GAMEND_CACHE_L2` | atom | `:partitioned` | redis or partitioned. Only used when mode is multi; partitioned needs clustering. |
| `GAMEND_CACHE_MAX_ENTRIES` | integer | `1000000` | Most entries each node's local cache holds. |
| `GAMEND_CACHE_MAX_MEMORY_MB` | integer | `500` | Most memory each node's local cache may use, in MB. Lower it on a small machine: the default alone is most of a 512 MB instance. |
| `GAMEND_CACHE_MODE` | atom | `:single` | single (L1 local only) or multi (L1 + a shared L2). |
| `GAMEND_CACHE_REDIS_POOL_SIZE` | integer | `10` |  |
| `GAMEND_CACHE_REDIS_URL` | string | - | Redis URL for the shared L2. **Required in production when `GAMEND_CACHE_MODE` is `multi` and `GAMEND_CACHE_L2` is `redis`.** |
| `GAMEND_CACHE_TTL_MS` | integer | `60000` | How long a cached entity (user, lobby, party, group, KV entry...) is kept, in ms. On a cluster it bounds how stale a node can be when an invalidation is missed. |


## Captcha

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_CAPTCHA_API_REGISTER` | boolean | `false` | Also require a captcha token (`captcha_token`) on POST /api/v1/register. Needs `enabled`; a client that cannot render the widget cannot register. |
| `GAMEND_CAPTCHA_ENABLED` | boolean | `false` | Require a captcha on the register and magic-link forms. |
| `GAMEND_CAPTCHA_SECRET_KEY` | string | - | Turnstile secret key, for server-side verification. **Required in production when `GAMEND_CAPTCHA_ENABLED` is `true`.** Secret - never log or commit it. |
| `GAMEND_CAPTCHA_SITE_KEY` | string | - | Turnstile sitekey (public, rendered into the page). Warns if unset when `GAMEND_CAPTCHA_ENABLED` is `true`. |
| `GAMEND_CAPTCHA_TIMEOUT_MS` | integer | `5000` | How long to wait for Cloudflare before giving up on a verification. |


## Client logs

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_CLIENT_LOGS_CATEGORY_LEVELS` | list | - | Per-category level overrides as category:level pairs, e.g. perf:off,network:warn. Overrides the floor for that category only; off drops it entirely. |
| `GAMEND_CLIENT_LOGS_ENABLED` | boolean | `false` | Accept log batches from game clients and re-emit them into the server's own logs, indexed at /admin/logs. |
| `GAMEND_CLIENT_LOGS_LEVEL` | string | `"info"` | Lowest client level to collect: trace, debug, info, warn or error. Clients gate their own uploads on this. |
| `GAMEND_CLIENT_LOGS_RETENTION_DAYS` | integer | `14` | Delete client sessions after N days of inactivity. 0 keeps them forever. |
| `GAMEND_CLIENT_LOGS_RETENTION_FLAGGED_DAYS` | integer | `90` | Retention for sessions marked flagged (any session that logged an error). |


## Clustering

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_CLUSTER_DNS_QUERY` | string | - | DNS name whose A/AAAA records list the other nodes, polled at boot. |
| `GAMEND_CLUSTER_REDIS_URL` | string | - | Shared fallback URL used by the cache and rate limiter when neither sets its own. |


## Content & plugins

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_CONTENT_APP_VERSION` | string | - | Version reported in the OpenAPI spec and admin pages. |
| `GAMEND_CONTENT_GEOIP_DB_PATH` | string | - | MaxMind mmdb file. Defaults to data/GeoLite2-Country.mmdb when present. |
| `GAMEND_CONTENT_PLUGINS_DIR` | string | `"modules/plugins"` | Directory containing OTP hook plugins. |
| `GAMEND_CONTENT_THEME_CONFIG` | string | - | Path to the theme JSON. A single file serves every locale; its text is translated via the gettext `theme` domain. |


## Database

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_DB_ADAPTER` | atom | `:sqlite` | sqlite or postgres. Compile-time; set as a build arg, not at boot. |
| `GAMEND_DB_IPV6` | boolean | `false` | Connect over IPv6, needed on platforms with IPv6-only private networking. |
| `GAMEND_DB_POOL_SIZE` | integer | - | Connections in the pool. Defaults to 10 on Postgres, 1 on SQLite. |
| `GAMEND_DB_POOL_TIMEOUT_MS` | integer | `10000` | How long a request waits to check out a connection, in milliseconds. |
| `GAMEND_DB_POSTGRES_DB` | string | - |  |
| `GAMEND_DB_POSTGRES_HOST` | string | - |  |
| `GAMEND_DB_POSTGRES_PASSWORD` | string | - | Secret - never log or commit it. |
| `GAMEND_DB_POSTGRES_PORT` | integer | `5432` |  |
| `GAMEND_DB_POSTGRES_SYNCHRONOUS_COMMIT` | atom | `:off` | on \| off \| local \| remote_write \| remote_apply. Defaults to `off`: up to ~600ms of commits are exposed to an OS crash in exchange for markedly faster writes. Payments always commit synchronously regardless. Postgres only. |
| `GAMEND_DB_POSTGRES_USER` | string | - |  |
| `GAMEND_DB_QUERY_TIMEOUT_MS` | integer | `15000` |  |
| `GAMEND_DB_QUEUE_INTERVAL_MS` | integer | `1000` |  |
| `GAMEND_DB_QUEUE_TARGET` | integer | `10000` |  |
| `GAMEND_DB_SQLITE_BUSY_TIMEOUT_MS` | integer | `15000` | Wait this long for a lock instead of failing with "database is locked". |
| `GAMEND_DB_SQLITE_CACHE_SIZE_KB` | integer | `200000` |  |
| `GAMEND_DB_SQLITE_PATH` | string | - | Where the SQLite file lives. Point at a mounted volume in production. |
| `GAMEND_DB_SQLITE_SYNCHRONOUS` | atom | `:normal` | off \| normal \| full \| extra. Lower means fewer fsyncs and less durability. |
| `GAMEND_DB_SQLITE_WAL_AUTOCHECKPOINT` | integer | `2000` |  |
| `GAMEND_DB_URL` | string | - | Full ecto:// URL. Takes precedence over the individual postgres_* values. Secret - never log or commit it. |


## Email

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_MAIL_SEND_TIMEOUT_MS` | integer | `30000` | Longest one email send may take before it is abandoned. gen_smtp itself waits up to 20 minutes for each reply from the relay. |
| `GAMEND_MAIL_SMTP_FROM_EMAIL` | string | - |  |
| `GAMEND_MAIL_SMTP_FROM_NAME` | string | `"Gamend"` |  |
| `GAMEND_MAIL_SMTP_PASSWORD` | string | - | SMTP password, or the provider's API key. Warns if unset once `GAMEND_MAIL_SMTP_RELAY` or `GAMEND_MAIL_SMTP_USERNAME` is set. Secret - never log or commit it. |
| `GAMEND_MAIL_SMTP_PORT` | integer | `465` |  |
| `GAMEND_MAIL_SMTP_RELAY` | string | - | SMTP host, e.g. smtp.resend.com. Warns if unset once `GAMEND_MAIL_SMTP_PASSWORD` or `GAMEND_MAIL_SMTP_USERNAME` is set. |
| `GAMEND_MAIL_SMTP_SNI` | string | - | TLS server name indication. Defaults to the relay host. |
| `GAMEND_MAIL_SMTP_SSL` | boolean | `true` |  |
| `GAMEND_MAIL_SMTP_TLS` | atom | `:never` | STARTTLS policy: never \| if_available \| always. |
| `GAMEND_MAIL_SMTP_USERNAME` | string | - | Warns if unset once `GAMEND_MAIL_SMTP_PASSWORD` or `GAMEND_MAIL_SMTP_RELAY` is set. |


## Hooks

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_HOOKS_CALL_TIMEOUT_IN_TRANSACTION_MS` | integer | `5000` | The same, for a hook called inside a database transaction: on SQLite that transaction holds the only write connection while the hook runs. |
| `GAMEND_HOOKS_CALL_TIMEOUT_MS` | integer | `60000` | How long a plugin hook or RPC may run before it is killed, in ms. The caller's request waits that long. |
| `GAMEND_HOOKS_SLOW_THRESHOLD_MS` | integer | `200` | Log a hook call as slow when it takes longer than this, in ms. |


## IndexNow

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_INDEX_NOW_ENABLED` | boolean | `false` | Notify IndexNow search engines (Bing, Yandex, Seznam — not Google) when pages change. |
| `GAMEND_INDEX_NOW_ENDPOINT` | string | `"https://api.indexnow.org/indexnow"` | IndexNow submission endpoint. Any participating engine's endpoint reaches all of them. |
| `GAMEND_INDEX_NOW_KEY` | string | - | IndexNow key, 8-128 hex characters. Public by design — it is served at /<key>.txt to prove domain ownership. Warns if unset when `GAMEND_INDEX_NOW_ENABLED` is `true`. |
| `GAMEND_INDEX_NOW_TIMEOUT_MS` | integer | `10000` | How long to wait for the IndexNow endpoint before giving up. |


## Limits

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_LIMITS_MATCHMAKING_DEFAULT_MAX_PLAYERS` | integer | `5` | Largest match a ticket forms when it does not say. At most max_matchmaking_players. |
| `GAMEND_LIMITS_MATCHMAKING_DEFAULT_MIN_PLAYERS` | integer | `2` | Smallest match a ticket forms when it does not say. |
| `GAMEND_LIMITS_MATCHMAKING_OFFLINE_GRACE_MS` | integer | `300000` | Grace before an offline player's ticket is pruned; long enough that a brief disconnect keeps its queue position. |
| `GAMEND_LIMITS_MATCHMAKING_TICK_MS` | integer | `3000` | Sweep interval of the matchmaking worker. |
| `GAMEND_LIMITS_MATCHMAKING_TIMEOUT_MS` | integer | `30000` | How long the oldest ticket waits before a below-max group still forms. |
| `GAMEND_LIMITS_MAX_ACTIVE_QUESTS_PER_USER` | integer | `200` | Progress rows a user may hold in the current periods; excess events are ignored. |
| `GAMEND_LIMITS_MAX_API_TOKENS_PER_USER` | integer | `10` | Personal API tokens one user may hold, revoked ones not counted. |
| `GAMEND_LIMITS_MAX_CHAT_CONTENT` | integer | `4096` |  |
| `GAMEND_LIMITS_MAX_CHAT_FILTER_WORDS` | integer | `10000` | Blocklist size cap. Sized to hold the bundled word lists for several languages. |
| `GAMEND_LIMITS_MAX_CHAT_FILTER_WORD_LEN` | integer | `64` |  |
| `GAMEND_LIMITS_MAX_CHAT_MESSAGES_PER_DAY` | integer | `5000` | Rolling 24h; 0 disables. Needs rate limiting on; ETS backend counts per instance. |
| `GAMEND_LIMITS_MAX_CHAT_REPORTS_PER_USER_PER_DAY` | integer | `50` | Rolling 24h; 0 disables. Needs rate limiting on; ETS backend counts per instance. |
| `GAMEND_LIMITS_MAX_DEVICE_ID` | integer | `256` |  |
| `GAMEND_LIMITS_MAX_DISPLAY_NAME` | integer | `255` | Max display-name length in codepoints. 255 is the users.display_name column's own limit on Postgres (varchar(255)); higher fails the insert there. |
| `GAMEND_LIMITS_MAX_EMAIL` | integer | `160` |  |
| `GAMEND_LIMITS_MAX_FRIENDS_PER_USER` | integer | `500` |  |
| `GAMEND_LIMITS_MAX_GROUPS_CREATED_PER_USER` | integer | `20` |  |
| `GAMEND_LIMITS_MAX_GROUPS_PER_USER` | integer | `50` |  |
| `GAMEND_LIMITS_MAX_GROUP_DESCRIPTION` | integer | `500` |  |
| `GAMEND_LIMITS_MAX_GROUP_MEMBERS` | integer | `10000` |  |
| `GAMEND_LIMITS_MAX_GROUP_PENDING_INVITES` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_GROUP_TITLE` | integer | `80` |  |
| `GAMEND_LIMITS_MAX_HOOK_ARGS_COUNT` | integer | `32` |  |
| `GAMEND_LIMITS_MAX_HOOK_ARGS_SIZE` | integer | `65536` |  |
| `GAMEND_LIMITS_MAX_KV_ENTRIES_PER_USER` | integer | `1000` |  |
| `GAMEND_LIMITS_MAX_KV_KEY` | integer | `512` |  |
| `GAMEND_LIMITS_MAX_KV_VALUE_SIZE` | integer | `65536` |  |
| `GAMEND_LIMITS_MAX_LEADERBOARD_DESCRIPTION` | integer | `1000` |  |
| `GAMEND_LIMITS_MAX_LEADERBOARD_SLUG` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_LEADERBOARD_TITLE` | integer | `255` |  |
| `GAMEND_LIMITS_MAX_LOBBY_PASSWORD` | integer | `128` |  |
| `GAMEND_LIMITS_MAX_LOBBY_TITLE` | integer | `80` |  |
| `GAMEND_LIMITS_MAX_LOBBY_USERS` | integer | `128` |  |
| `GAMEND_LIMITS_MAX_MATCHMAKING_PARAMS_SIZE` | integer | `2048` | Serialized byte size of a ticket's match_params map. |
| `GAMEND_LIMITS_MAX_MATCHMAKING_PLAYERS` | integer | `64` | Hard cap on a ticket's own max_players setting. |
| `GAMEND_LIMITS_MAX_METADATA_SIZE` | integer | `16384` |  |
| `GAMEND_LIMITS_MAX_MUTE_REASON` | integer | `500` |  |
| `GAMEND_LIMITS_MAX_NOTIFICATIONS_PER_USER` | integer | `500` |  |
| `GAMEND_LIMITS_MAX_NOTIFICATION_CONTENT` | integer | `10000` |  |
| `GAMEND_LIMITS_MAX_NOTIFICATION_TITLE` | integer | `255` |  |
| `GAMEND_LIMITS_MAX_OBJECTIVES_PER_QUEST` | integer | `10` |  |
| `GAMEND_LIMITS_MAX_PAGE_SIZE` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_PARTY_PENDING_INVITES` | integer | `20` |  |
| `GAMEND_LIMITS_MAX_PARTY_SIZE` | integer | `32` |  |
| `GAMEND_LIMITS_MAX_PENDING_FRIEND_REQUESTS` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_PROFILE_URL` | integer | `2048` |  |
| `GAMEND_LIMITS_MAX_PUSH_BODY` | integer | `4000` |  |
| `GAMEND_LIMITS_MAX_PUSH_DATA_SIZE` | integer | `4096` | Serialized byte size of a push message's custom data map. |
| `GAMEND_LIMITS_MAX_PUSH_TITLE` | integer | `255` |  |
| `GAMEND_LIMITS_MAX_PUSH_TOKENS_PER_USER` | integer | `20` | Live (non-disabled) device tokens per user. |
| `GAMEND_LIMITS_MAX_QUESTS` | integer | `500` |  |
| `GAMEND_LIMITS_MAX_QUEST_CATEGORY` | integer | `64` |  |
| `GAMEND_LIMITS_MAX_QUEST_DESCRIPTION` | integer | `1000` |  |
| `GAMEND_LIMITS_MAX_QUEST_KEY` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_QUEST_PERIOD_HISTORY` | integer | `90` | Days of daily/weekly period history kept before the retention prune. |
| `GAMEND_LIMITS_MAX_QUEST_REWARD_ENTRIES` | integer | `10` |  |
| `GAMEND_LIMITS_MAX_QUEST_TITLE` | integer | `255` |  |
| `GAMEND_LIMITS_MAX_READY_CHECK_PARTICIPANTS` | integer | `64` | Hard cap on participants in one check. |
| `GAMEND_LIMITS_MAX_REPORT_REASON` | integer | `500` |  |
| `GAMEND_LIMITS_MAX_SOCKETS_PER_USER` | integer | `20` | Concurrent sockets per user. 0 disables; counted per app instance. |
| `GAMEND_LIMITS_MAX_TOURNAMENT_BRACKET_SIZE` | integer | `256` |  |
| `GAMEND_LIMITS_MAX_TOURNAMENT_DESCRIPTION` | integer | `1000` |  |
| `GAMEND_LIMITS_MAX_TOURNAMENT_ENTRIES` | integer | `10000` | Hard cap on a tournament's own max_entries setting. |
| `GAMEND_LIMITS_MAX_TOURNAMENT_SLUG` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_TOURNAMENT_TITLE` | integer | `255` |  |
| `GAMEND_LIMITS_MAX_UPLOAD_BYTES` | integer | `5242880` | Max size of a single uploaded object (avatars/UGC). 5 MiB. |
| `GAMEND_LIMITS_MAX_UPLOAD_BYTES_PER_OWNER` | integer | `52428800` | Max total bytes one owner may hold under an upload prefix. Caps the orphans left by tickets a client requests but never confirms. 50 MiB. |
| `GAMEND_LIMITS_MAX_USERNAME` | integer | `32` |  |
| `GAMEND_LIMITS_MIN_USERNAME` | integer | `3` |  |
| `GAMEND_LIMITS_READY_CHECK_TIMEOUT_MS` | integer | `15000` | Default answering window. Overridable per check by the caller. |
| `GAMEND_LIMITS_USERNAME_ASCII_ONLY` | boolean | `false` | Keep username handles to a-z, 0-9 and . _ - (the GitHub and Discord model). Input is still normalized first, so WANG in fullwidth becomes wang; display names stay Unicode. |


## Lobby snapshots

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_LOBBY_SNAPSHOTS_ENABLED` | boolean | `false` | Record a durable per-run snapshot of lobby state, browsable at /admin/lobby_snapshots. |
| `GAMEND_LOBBY_SNAPSHOTS_MAX_KV_ENTRIES` | integer | `200` | Cap on KV entries captured per snapshot. |
| `GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS` | list | - | User-scoped KV keys to capture. Empty captures none — the widest exposure in a snapshot. |


## OAuth providers

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_OAUTH_APPLE_CLIENT_ID` | string | - | Services id (web audience) for Sign in with Apple. Warns if unset once `GAMEND_OAUTH_APPLE_TEAM_ID`, `GAMEND_OAUTH_APPLE_KEY_ID` or `GAMEND_OAUTH_APPLE_PRIVATE_KEY` is set. |
| `GAMEND_OAUTH_APPLE_ENABLED` | boolean | `true` | Offer apple sign-in. Only takes effect once its credentials are set. |
| `GAMEND_OAUTH_APPLE_IOS_CLIENT_ID` | string | - | Bundle id (iOS audience) used when verifying Apple ID tokens. |
| `GAMEND_OAUTH_APPLE_KEY_ID` | string | - | Key id of the Sign in with Apple auth key (Apple Developer -> Keys). Warns if unset once `GAMEND_OAUTH_APPLE_CLIENT_ID`, `GAMEND_OAUTH_APPLE_TEAM_ID` or `GAMEND_OAUTH_APPLE_PRIVATE_KEY` is set. |
| `GAMEND_OAUTH_APPLE_PRIVATE_KEY` | string | - | Contents of the Sign in with Apple .p8 key. Warns if unset once `GAMEND_OAUTH_APPLE_CLIENT_ID`, `GAMEND_OAUTH_APPLE_TEAM_ID` or `GAMEND_OAUTH_APPLE_KEY_ID` is set. Secret - never log or commit it. |
| `GAMEND_OAUTH_APPLE_TEAM_ID` | string | - | Warns if unset once `GAMEND_OAUTH_APPLE_CLIENT_ID`, `GAMEND_OAUTH_APPLE_KEY_ID` or `GAMEND_OAUTH_APPLE_PRIVATE_KEY` is set. |
| `GAMEND_OAUTH_DISCORD_CLIENT_ID` | string | - | Warns if unset once `GAMEND_OAUTH_DISCORD_CLIENT_SECRET` is set. |
| `GAMEND_OAUTH_DISCORD_CLIENT_SECRET` | string | - | Warns if unset once `GAMEND_OAUTH_DISCORD_CLIENT_ID` is set. Secret - never log or commit it. |
| `GAMEND_OAUTH_DISCORD_ENABLED` | boolean | `true` | Offer discord sign-in. Only takes effect once its credentials are set. |
| `GAMEND_OAUTH_FACEBOOK_CLIENT_ID` | string | - | Warns if unset once `GAMEND_OAUTH_FACEBOOK_CLIENT_SECRET` is set. |
| `GAMEND_OAUTH_FACEBOOK_CLIENT_SECRET` | string | - | Warns if unset once `GAMEND_OAUTH_FACEBOOK_CLIENT_ID` is set. Secret - never log or commit it. |
| `GAMEND_OAUTH_FACEBOOK_ENABLED` | boolean | `true` | Offer facebook sign-in. Only takes effect once its credentials are set. |
| `GAMEND_OAUTH_GITHUB_CLIENT_ID` | string | - | Warns if unset once `GAMEND_OAUTH_GITHUB_CLIENT_SECRET` is set. |
| `GAMEND_OAUTH_GITHUB_CLIENT_SECRET` | string | - | Warns if unset once `GAMEND_OAUTH_GITHUB_CLIENT_ID` is set. Secret - never log or commit it. |
| `GAMEND_OAUTH_GITHUB_ENABLED` | boolean | `true` | Offer github sign-in. Only takes effect once its credentials are set. |
| `GAMEND_OAUTH_GOOGLE_CLIENT_ID` | string | - | Warns if unset once `GAMEND_OAUTH_GOOGLE_CLIENT_SECRET` is set. |
| `GAMEND_OAUTH_GOOGLE_CLIENT_SECRET` | string | - | Warns if unset once `GAMEND_OAUTH_GOOGLE_CLIENT_ID` is set. Secret - never log or commit it. |
| `GAMEND_OAUTH_GOOGLE_ENABLED` | boolean | `true` | Offer google sign-in. Only takes effect once its credentials are set. |
| `GAMEND_OAUTH_GOOGLE_WEB_CLIENT_ID` | string | - | Native-app client id used to verify Google ID tokens from SDK sign-in. |
| `GAMEND_OAUTH_STEAM_API_KEY` | string | - | Steam Web API key, used for OpenID sign-in. Secret - never log or commit it. |
| `GAMEND_OAUTH_STEAM_APP_ID` | string | - |  |
| `GAMEND_OAUTH_STEAM_ENABLED` | boolean | `true` | Offer steam sign-in. Only takes effect once its credentials are set. |


## Observability

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_OBSERVABILITY_ACCESS_LOG_LEVEL` | log_level | `:debug` | Level for per-request access logs, or `off` to silence them. |
| `GAMEND_OBSERVABILITY_GRAFANA_URL` | string | - | Public Grafana URL linked from the admin dashboard, if you host one. |
| `GAMEND_OBSERVABILITY_LOG_FILE_LEVEL` | log_level | `:info` | Level for the rotating file handler. |
| `GAMEND_OBSERVABILITY_LOG_FILE_MAX_BYTES` | integer | `10000000` | Bytes per rotated file. |
| `GAMEND_OBSERVABILITY_LOG_FILE_MAX_FILES` | integer | `5` | How many rotated files to keep. With the default size, ~50MB of disk. |
| `GAMEND_OBSERVABILITY_LOG_FILE_PATH` | string | - | Write a rotating log file alongside stdout. Unset disables the file handler. |
| `GAMEND_OBSERVABILITY_LOG_LEVEL` | log_level | `:info` | Application log level: debug \| info \| warning \| error. |
| `GAMEND_OBSERVABILITY_METRICS_TOKEN` | string | - | When set, every non-loopback /metrics scrape must send `Authorization: Bearer <token>`. Accepts the token inline or a path to a file holding it (e.g. a docker secret). Secret - never log or commit it. |


## Payments

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_PAYMENTS_APPLE_APP_STORE_SERVER_BASE_URL` | string | - |  |
| `GAMEND_PAYMENTS_APPLE_BUNDLE_ID` | string | - | Warns if unset once `GAMEND_PAYMENTS_APPLE_ISSUER_ID` or `GAMEND_PAYMENTS_APPLE_KEY_ID` is set. |
| `GAMEND_PAYMENTS_APPLE_ISSUER_ID` | string | - | Issuer id from App Store Connect -> Users and Access -> Integrations. Warns if unset once `GAMEND_PAYMENTS_APPLE_BUNDLE_ID` or `GAMEND_PAYMENTS_APPLE_KEY_ID` is set. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_APPLE_KEY_ID` | string | - | Key id of the App Store Connect API key — not the Sign in with Apple key. Warns if unset once `GAMEND_PAYMENTS_APPLE_BUNDLE_ID` or `GAMEND_PAYMENTS_APPLE_ISSUER_ID` is set. |
| `GAMEND_PAYMENTS_APPLE_PRIVATE_KEY` | string | - | Inline .p8 contents for the App Store Connect API key. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_APPLE_PRIVATE_KEY_PATH` | string | - |  |
| `GAMEND_PAYMENTS_ENVIRONMENT` | atom | `:production` | sandbox while validating, production for real transactions. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_ACCESS_TOKEN` | string | - | Secret - never log or commit it. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_AUTO_ACKNOWLEDGE` | boolean | `false` |  |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME` | string | - | Warns if unset once `GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` is set. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_PUBLISHER_BASE_URL` | string | - |  |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN` | string | - | Shared bearer token on the Pub/Sub push webhook. Without it the RTDN endpoint fails closed in production. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | string | - | Inline service-account JSON. Use the _PATH variant to read it from a file instead. Warns if unset once `GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME` is set. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | string | - |  |
| `GAMEND_PAYMENTS_STEAM_APP_ID` | string | - |  |
| `GAMEND_PAYMENTS_STEAM_MICROTXN_BASE_URL` | string | - |  |
| `GAMEND_PAYMENTS_STEAM_WEB_API_KEY` | string | - | Falls back to the OAuth Steam key when unset. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_API_VERSION` | string | `"2022-11-15"` |  |
| `GAMEND_PAYMENTS_STRIPE_MANAGED_PAYMENTS` | boolean | `false` | Sell through Stripe Managed Payments (Stripe is merchant of record: it charges and remits the buyer's VAT). Accept the terms and set a tax code on every product in the Stripe Dashboard first. |
| `GAMEND_PAYMENTS_STRIPE_PRODUCTION_SECRET_KEY` | string | - | sk_live_... key, used when environment is production. Warns if unset when `GAMEND_PAYMENTS_ENVIRONMENT` is `production`. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_PRODUCTION_WEBHOOK_SECRET` | string | - | Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_SANDBOX_SECRET_KEY` | string | - | sk_test_... key, used when environment is sandbox. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET` | string | - | Secret - never log or commit it. |


## Presence

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_PRESENCE_INTERVAL_MS` | integer | `120000` | How often users still marked online after a crash are looked for, in ms. |
| `GAMEND_PRESENCE_STALE_THRESHOLD_S` | integer | `300` | Mark a user offline once their last_seen_at is this many seconds old. Connected sockets refresh it at three fifths of this, at most every 3 minutes. |


## Public features

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_FEATURES_LIST_GROUPS` | boolean | `true` | GET /api/v1/groups*, the "groups" channel and the /groups pages. |
| `GAMEND_FEATURES_LIST_LEADERBOARDS` | boolean | `true` | Public GET/resolve /api/v1/leaderboards* and the /leaderboards pages. |
| `GAMEND_FEATURES_LIST_LOBBIES` | boolean | `true` | GET /api/v1/lobbies and the "lobbies" channel. |
| `GAMEND_FEATURES_LIST_MATCHMAKING` | boolean | `true` | GET /api/v1/matchmaking/stats. Own-ticket endpoints stay. |
| `GAMEND_FEATURES_LIST_QUESTS` | boolean | `true` | Public GET /api/v1/quests* and the /quests page. |
| `GAMEND_FEATURES_LIST_TOURNAMENTS` | boolean | `true` | Public GET /api/v1/tournaments* and the /tournaments pages. |
| `GAMEND_FEATURES_LIST_USERS` | boolean | `true` | GET /api/v1/users and /users/:id. |
| `GAMEND_FEATURES_MAILBOX_PREVIEW` | boolean | `false` | Serve the in-browser mailbox at /dev/mailbox outside dev. Every sent email is readable there. |
| `GAMEND_FEATURES_OPENAPI` | boolean | `true` | OpenAPI spec + Swagger UI. A complete map of your API — consider off in production. |
| `GAMEND_FEATURES_PLAY` | boolean | `true` | The /play page, which hands a signed-in player a token for the game client. |
| `GAMEND_FEATURES_PUBLIC_STATS` | boolean | `true` | The unauthenticated stats endpoints: GET /api/v1/stats, /api/v1/users/stats, /api/v1/lobbies/stats, /api/v1/parties/stats, /api/v1/quests/stats, /api/v1/signaling/stats and /api/v1/matchmaking/stats, plus the /stats page. Aggregate counts only, never per-row data — but they do reveal how busy the server is. |
| `GAMEND_FEATURES_PUBLIC_USER_METADATA_KEYS` | list | - | Top-level `user.metadata` keys GET /api/v1/users and /users/:id may return. Empty means none. Those endpoints are unauthenticated, so anything named here is world-readable and findable by name prefix — never list a key holding position, routing or contact data. |
| `GAMEND_FEATURES_USER_IMAGE_UPLOADS` | boolean | `true` | Player-supplied images: avatars (POST /api/v1/me/avatar*) and group icons (POST /api/v1/groups/:id/icon*). Objects land in public storage and are served without authentication, so on a service children can reach this is an unscreened image surface — turn it off unless the game actually uses it and you have a way to screen what arrives. |


## Push notifications

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_PUSH_ADAPTER` | atom | `:auto` | Set to `log` to route every delivery to the Log provider, credentials or not. |
| `GAMEND_PUSH_APNS_ENV` | atom | `:production` | `production`, or `sandbox` for dev builds. |
| `GAMEND_PUSH_APNS_KEY_ID` | string | - | 10-character key id of the APNs auth key. Warns if unset once `GAMEND_PUSH_APNS_PRIVATE_KEY`, `GAMEND_PUSH_APNS_TEAM_ID` or `GAMEND_PUSH_APNS_TOPIC` is set. |
| `GAMEND_PUSH_APNS_PRIVATE_KEY` | string | - | APNs .p8 key contents, or a path to the file. Warns if unset once `GAMEND_PUSH_APNS_KEY_ID`, `GAMEND_PUSH_APNS_TEAM_ID` or `GAMEND_PUSH_APNS_TOPIC` is set. Secret - never log or commit it. |
| `GAMEND_PUSH_APNS_TEAM_ID` | string | - | Apple developer team id. Warns if unset once `GAMEND_PUSH_APNS_PRIVATE_KEY`, `GAMEND_PUSH_APNS_KEY_ID` or `GAMEND_PUSH_APNS_TOPIC` is set. |
| `GAMEND_PUSH_APNS_TOPIC` | string | - | App bundle id, sent as apns-topic. Warns if unset once `GAMEND_PUSH_APNS_PRIVATE_KEY`, `GAMEND_PUSH_APNS_KEY_ID` or `GAMEND_PUSH_APNS_TEAM_ID` is set. |
| `GAMEND_PUSH_FCM_CREDENTIALS` | string | - | FCM service-account JSON, inline or a path to the file. Secret - never log or commit it. |
| `GAMEND_PUSH_FCM_PROJECT_ID` | string | - | Defaults to the project id inside the FCM credentials. |
| `GAMEND_PUSH_QUEUE_CONCURRENCY` | integer | `10` | Per-node concurrent deliveries on the push queue. |


## Rate limiting

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_RATELIMIT_AUTH_LIMIT` | integer | `10` | Max login/register requests per window, per IP. |
| `GAMEND_RATELIMIT_AUTH_WINDOW_MS` | integer | `60000` | Auth HTTP window, in milliseconds. |
| `GAMEND_RATELIMIT_BACKEND` | atom | `:ets` | ets (per-node counters) or redis (shared across instances). |
| `GAMEND_RATELIMIT_CLIENT_LOGS_LIMIT` | integer | `30` | Max client log batch uploads per window, per IP. |
| `GAMEND_RATELIMIT_CLIENT_LOGS_WINDOW_MS` | integer | `60000` | Client log upload window, in milliseconds. |
| `GAMEND_RATELIMIT_DC_LIMIT` | integer | `300` | Max WebRTC DataChannel messages per window, per user. |
| `GAMEND_RATELIMIT_DC_WINDOW_MS` | integer | `10000` | WebRTC DataChannel window, in milliseconds. |
| `GAMEND_RATELIMIT_ENABLED` | boolean | `true` | Master switch for all request/message throttling. |
| `GAMEND_RATELIMIT_GENERAL_LIMIT` | integer | `240` | Max general HTTP requests per window, per IP. |
| `GAMEND_RATELIMIT_GENERAL_WINDOW_MS` | integer | `60000` | General HTTP window, in milliseconds. |
| `GAMEND_RATELIMIT_ICE_LIMIT` | integer | `150` | Max ICE candidate messages per window, per user. |
| `GAMEND_RATELIMIT_ICE_WINDOW_MS` | integer | `30000` | ICE candidate window, in milliseconds. |
| `GAMEND_RATELIMIT_REDIS_URL` | string | - | Redis URL for shared counters. **Required in production when `GAMEND_RATELIMIT_BACKEND` is `redis`.** |
| `GAMEND_RATELIMIT_SIGNALING_ICE_LIMIT` | integer | `150` | Max ICE candidates relayed over the signaling channel per window, per user. |
| `GAMEND_RATELIMIT_SIGNALING_ICE_WINDOW_MS` | integer | `30000` | Signaling ICE window, in milliseconds. |
| `GAMEND_RATELIMIT_SIGNALING_WS_LIMIT` | integer | `300` | Max signaling channel messages per window, per user. |
| `GAMEND_RATELIMIT_SIGNALING_WS_WINDOW_MS` | integer | `10000` | Signaling channel window, in milliseconds. |
| `GAMEND_RATELIMIT_WS_LIMIT` | integer | `60` | Max WebSocket channel messages per window, per user. |
| `GAMEND_RATELIMIT_WS_WINDOW_MS` | integer | `10000` | WebSocket window, in milliseconds. |


## Realtime

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_REALTIME_DEBOUNCE_MS` | integer | `0` | Hold outbound state updates this long and push only the latest per object. 0 pushes immediately. |
| `GAMEND_REALTIME_PRESENCE_POOL_SIZE` | integer | `1` | Phoenix.Presence tracker shards. Must match on every node in a cluster; needs a full restart to change. |
| `GAMEND_REALTIME_PUBSUB_POOL_SIZE` | integer | `1` | Phoenix.PubSub shards. Raise on nodes holding many thousands of sockets. |
| `GAMEND_REALTIME_SOCKET_BUFFER_KB` | integer | `0` | Cap the per-connection socket read buffer, in KB. 0 leaves the OS default. Only lowers memory on platforms that honour it; does not change the TCP window. |


## Retention

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES` | integer | `15` | Delete lobbies nobody has been seen in for N minutes, and release the seat of a player offline that long in a lobby still in use. 0 disables both. |
| `GAMEND_RETENTION_ABANDONED_PARTY_MINUTES` | integer | `15` | Disband parties nobody has been seen in for N minutes. 0 disables. |
| `GAMEND_RETENTION_ACTIVITY_DAYS` | integer | `0` | Delete per-user daily activity rows (DAU / D1-D7-D30 source) older than N days. 0 keeps forever. Below 60 the admin retention cohorts go blank. |
| `GAMEND_RETENTION_ANONYMOUS_USERS_DAYS` | integer | `90` | Delete device-only accounts inactive for N days. 0 keeps forever. These accounts cost one unauthenticated request to create, so they are the tier that actually needs a sweep. |
| `GAMEND_RETENTION_BATCH_SIZE` | integer | `500` | Rows deleted per statement. Lower it if a sweep stalls gameplay writes on SQLite, where each statement holds the write lock. |
| `GAMEND_RETENTION_CHAT_MESSAGES_DAYS` | integer | `0` | Delete chat messages older than N days. 0 keeps forever. |
| `GAMEND_RETENTION_INACTIVE_USERS_DAYS` | integer | `0` | Delete accounts with a real identity after N days of inactivity. 0 (the default) keeps forever - deleting a player who comes back is worse than the storage. 730 matches what Google and Microsoft use if you turn it on. |
| `GAMEND_RETENTION_INACTIVE_USERS_WARN_DAYS` | integer | `30` | Email a warning this many days before an inactive account is deleted. 0 deletes with no warning. Accounts with no email address cannot be warned. |
| `GAMEND_RETENTION_INTERVAL_HOURS` | integer | `6` | Hours between full retention sweeps. The first runs five minutes after boot. |
| `GAMEND_RETENTION_INVITES_DAYS` | integer | `30` | Delete resolved invites and join requests N days after resolution. |
| `GAMEND_RETENTION_LEDGER_DAYS` | integer | `0` | Delete wallet/inventory ledger entries older than N days. 0 keeps forever. |
| `GAMEND_RETENTION_LIVE_INTERVAL_SECONDS` | integer | `60` | Seconds between sweeps of the classes that free live state: offline lobby and party seats, abandoned parties, abandoned lobbies. 0 leaves them to the full sweep. |
| `GAMEND_RETENTION_LOBBY_SNAPSHOTS_DAYS` | integer | `30` | Delete lobby snapshots, events and blobs older than N days. |
| `GAMEND_RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` | integer | `90` | Longer window for snapshots of runs flagged anomalous. |
| `GAMEND_RETENTION_MATCHMAKING_TICKETS_HOURS` | integer | `24` | Delete matchmaking tickets older than N hours, in any status. |
| `GAMEND_RETENTION_NOTIFICATIONS_DAYS` | integer | `0` | Delete notifications older than N days. 0 keeps forever. |
| `GAMEND_RETENTION_PAYMENT_EVENTS_DAYS` | integer | `0` | Delete payment provider webhook events older than N days. Purchases are never pruned. |
| `GAMEND_RETENTION_PUSH_TOKENS_DAYS` | integer | `270` | Delete push tokens untouched for N days. Defaults to Google's stale-token guidance. |
| `GAMEND_RETENTION_TOURNAMENTS_DAYS` | integer | `0` | Delete finished tournaments older than N days. 0 keeps forever. |
| `GAMEND_RETENTION_UNCONFIRMED_USERS_DAYS` | integer | `30` | Delete email accounts that never confirmed their address and have been inactive for N days. 0 keeps forever. Accounts that also have a provider login are kept. |


## Secrets

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_SECRETS_KEYS` | string | - | Comma-separated id:key pairs for encrypting customer secrets, each key 32 bytes base64. The first is used for new writes; the rest let rows written before a rotation still be read. Unset disables the store. Secret - never log or commit it. |


## Server & HTTP

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_HTTP_ALLOWED_ORIGINS` | list | - | Browser CORS/WebSocket origin allowlist. Empty allows any origin. Prefix an entry with `regex:` for a pattern. |
| `GAMEND_HTTP_CLIENT_RETRIES` | integer | `1` | Retries of a failed GET to a provider. POSTs are never retried. 0 disables. |
| `GAMEND_HTTP_CLIENT_TIMEOUT_MS` | integer | `10000` | Per-try timeout for calls to payment, OAuth and avatar providers, in milliseconds: connecting, and waiting for the response. |
| `GAMEND_HTTP_HOST` | string | `"localhost"` | Public hostname, used to build URLs and OAuth redirect URIs. |
| `GAMEND_HTTP_MAX_BODY_BYTES` | integer | `1048576` | Largest request body the server reads (JSON, form or multipart), in bytes. Raise it with any GAMEND_LIMITS_* size above 1 MB, or requests that size are refused first. Local-backend uploads are capped by GAMEND_LIMITS_MAX_UPLOAD_BYTES instead. |
| `GAMEND_HTTP_PORT` | integer | `4000` | TCP port the HTTP listener binds. |
| `GAMEND_HTTP_SCHEME` | string | - | http or https. Defaults to http for localhost, https otherwise. |
| `GAMEND_HTTP_SERVER` | boolean | `false` | Start the HTTP listener. Only needed when running as a release. |


## Storage

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_STORAGE_ACCESS_KEY_ID` | string | - | **Required in production when `GAMEND_STORAGE_ADAPTER` is `s3`.** Secret - never log or commit it. |
| `GAMEND_STORAGE_ADAPTER` | atom | `:local` | Backend for avatars and uploads: local \| s3 (any S3-compatible service). |
| `GAMEND_STORAGE_BUCKET` | string | - | **Required in production when `GAMEND_STORAGE_ADAPTER` is `s3`.** |
| `GAMEND_STORAGE_DIR` | string | `"priv/storage"` | Directory the local adapter writes objects to. Point this at persistent storage (a mounted volume) in production — the default lives with the app and does not survive a redeploy. |
| `GAMEND_STORAGE_ENDPOINT` | string | - | Custom endpoint, e.g. https://<account>.r2.cloudflarestorage.com. |
| `GAMEND_STORAGE_PUBLIC_URL` | string | - | CDN or base URL serving stored objects, whichever backend is behind it. |
| `GAMEND_STORAGE_REGION` | string | `"auto"` | Region, or "auto" for services that do not use one (R2, MinIO). |
| `GAMEND_STORAGE_SECRET_ACCESS_KEY` | string | - | **Required in production when `GAMEND_STORAGE_ADAPTER` is `s3`.** Secret - never log or commit it. |
| `GAMEND_STORAGE_SIGNED_URL_SECONDS` | integer | `3600` | Lifetime of the signed link /storage/<key> redirects to, for an S3 bucket with no public_url. S3 caps it at 604800 (7 days). |
| `GAMEND_STORAGE_UPLOAD_TTL_SECONDS` | integer | `600` | How long an upload ticket stays valid, in seconds. Raise it for large uploads over slow connections. |


## TLS & certificates

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_TLS_ACME_WEBROOT` | string | - | Webroot for Let's Encrypt HTTP-01 challenge files. Defaults to /var/www/acme. |
| `GAMEND_TLS_CERTFILE` | string | - | Path to fullchain.pem (certificate + CA chain). Warns if unset once `GAMEND_TLS_KEYFILE` is set. |
| `GAMEND_TLS_FORCE` | boolean | - | Redirect HTTP to HTTPS. Off unless set: a host that serves port 80 itself keeps a plain-HTTP twin of every page until you enable it. Read per request by GamendWeb.Plugs.ForceSSL; HSTS is sent on every HTTPS response regardless, by GamendWeb.Plugs.SecurityHeaders. |
| `GAMEND_TLS_KEYFILE` | string | - | Path to privkey.pem. Warns if unset once `GAMEND_TLS_CERTFILE` is set. |
| `GAMEND_TLS_PORT` | integer | `443` | HTTPS listen port. |


## Tournaments

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_TOURNAMENTS_TICK_INTERVAL_SECONDS` | integer | `30` | Seconds between tournament ticks: state transitions, match-ready, deadline sweeps and recurrence. A round can start or time out up to this late. |


## WebRTC

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_WEBRTC_STUN_URLS` | list | `stun:stun.l.google.com:19302` | Comma-separated STUN server URLs. Empty uses none. |
| `GAMEND_WEBRTC_TURN_CREDENTIAL` | string | - | Credential for the TURN servers. Warns if unset once `GAMEND_WEBRTC_TURN_USERNAME` is set. Secret - never log or commit it. |
| `GAMEND_WEBRTC_TURN_URLS` | list | - | Comma-separated TURN server URLs (turn:host:3478, turns:host:5349). Empty uses none. Only needed when the server itself is behind NAT or UDP is filtered. |
| `GAMEND_WEBRTC_TURN_USERNAME` | string | - | Username for the TURN servers. Warns if unset once `GAMEND_WEBRTC_TURN_CREDENTIAL` is set. |

