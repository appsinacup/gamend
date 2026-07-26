---
icon: hero-adjustments-horizontal
generated: by `mix gamend.settings.guide` - do not edit by hand; edit the
  declaration in the module that owns the setting
---

# Settings

Every setting the server has, with the environment variable that sets it.
211 settings across 19 groups.

A setting is declared in the module that owns it, so this page and
`.env.example` are generated from the same source the server reads. The
variable name is derived from the declaration rather than written by hand.

Environment variables are one *input method*. A host can configure the
ordinary Elixir way instead, and everything ends at `Application` config:

```elixir
config :game_server_core, GameServer.Retention, chat_messages_days: 90
```

To feed the variables below in, a host adds one line to
`config/runtime.exs`:

```elixir
for {app, module, opts} <- GameServer.Settings.from_env() do
  config app, module, opts
end
```

Live values, and where each one came from, are on the
[admin settings page](/admin/settings).


## Authentication

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_AUTH_DEVICE_AUTH_ENABLED` | boolean | `true` | Allow POST /api/v1/login/device. When on, any unknown device_id creates an anonymous account. |
| `GAMEND_AUTH_GUARDIAN_SECRET_KEY` | string | - | JWT signing key. Defaults to secret_key_base when unset. Secret - never log or commit it. |
| `GAMEND_AUTH_MIN_PASSWORD_LENGTH` | integer | `8` | Minimum password length enforced at registration and change. |
| `GAMEND_AUTH_REQUIRE_ACTIVATION` | boolean | `false` | New accounts cannot log in until an admin activates them (beta mode). |
| `GAMEND_AUTH_SECRET_KEY_BASE` | string | - | Signs and encrypts cookies, tokens and LiveView sessions. **Required in production.** Secret - never log or commit it. |


## Cache

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_CACHE_ENABLED` | boolean | `true` | Set false to bypass caching entirely. |
| `GAMEND_CACHE_L2` | atom | `:partitioned` | redis or partitioned. Only used when mode is multi; partitioned needs clustering. |
| `GAMEND_CACHE_MODE` | atom | `:single` | single (L1 local only) or multi (L1 + a shared L2). |
| `GAMEND_CACHE_REDIS_POOL_SIZE` | integer | `10` |  |
| `GAMEND_CACHE_REDIS_URL` | string | - | Redis URL for the shared L2. **Required in production.** |


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
| `GAMEND_DB_POOL_SIZE` | integer | - | Connections in the pool. Defaults to 10 on Postgres, 5 on SQLite. |
| `GAMEND_DB_POOL_TIMEOUT_MS` | integer | `10000` | How long a request waits to check out a connection, in milliseconds. |
| `GAMEND_DB_POSTGRES_DB` | string | - |  |
| `GAMEND_DB_POSTGRES_HOST` | string | - |  |
| `GAMEND_DB_POSTGRES_PASSWORD` | string | - | Secret - never log or commit it. |
| `GAMEND_DB_POSTGRES_PORT` | integer | `5432` |  |
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


## Public features

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_FEATURES_LIST_GROUPS` | boolean | `true` | GET /api/v1/groups*, the "groups" channel and the /groups pages. |
| `GAMEND_FEATURES_LIST_LEADERBOARDS` | boolean | `true` | Public GET/resolve /api/v1/leaderboards* and the /leaderboards pages. |
| `GAMEND_FEATURES_LIST_LOBBIES` | boolean | `true` | GET /api/v1/lobbies and the "lobbies" channel. |
| `GAMEND_FEATURES_LIST_MATCHMAKING` | boolean | `true` | GET /api/v1/matchmaking/stats. Own-ticket endpoints stay. |
| `GAMEND_FEATURES_LIST_QUESTS` | boolean | `true` | Public GET /api/v1/quests* and the /quests page. |
| `GAMEND_FEATURES_LIST_USERS` | boolean | `true` | GET /api/v1/users and /users/:id. |
| `GAMEND_FEATURES_MAILBOX_PREVIEW` | boolean | `false` | Serve the in-browser mailbox at /dev/mailbox outside dev. Every sent email is readable there. |
| `GAMEND_FEATURES_OPENAPI` | boolean | `true` | OpenAPI spec + Swagger UI. A complete map of your API — consider off in production. |


## Server & HTTP

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_HTTP_ALLOWED_ORIGINS` | list | `` | Browser CORS/WebSocket origin allowlist. Empty allows any origin. Prefix an entry with `regex:` for a pattern. |
| `GAMEND_HTTP_HOST` | string | `"localhost"` | Public hostname, used to build URLs and OAuth redirect URIs. |
| `GAMEND_HTTP_PORT` | integer | `4000` | TCP port the HTTP listener binds. |
| `GAMEND_HTTP_SCHEME` | string | - | http or https. Defaults to http for localhost, https otherwise. |
| `GAMEND_HTTP_SERVER` | boolean | `false` | Start the HTTP listener. Only needed when running as a release. |


## Limits

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_LIMITS_MATCHMAKING_OFFLINE_GRACE_MS` | integer | `300000` | Grace before an offline player's ticket is pruned; long enough that a brief disconnect keeps its queue position. |
| `GAMEND_LIMITS_MATCHMAKING_TICK_MS` | integer | `3000` | Sweep interval of the matchmaking worker. |
| `GAMEND_LIMITS_MATCHMAKING_TIMEOUT_MS` | integer | `30000` | How long the oldest ticket waits before a below-max group still forms. |
| `GAMEND_LIMITS_MAX_ACTIVE_QUESTS_PER_USER` | integer | `200` | Progress rows a user may hold in the current periods; excess events are ignored. |
| `GAMEND_LIMITS_MAX_CHAT_CONTENT` | integer | `4096` |  |
| `GAMEND_LIMITS_MAX_CHAT_MESSAGES_PER_DAY` | integer | `5000` | Rolling 24h; 0 disables. Needs rate limiting on; ETS backend counts per instance. |
| `GAMEND_LIMITS_MAX_DEVICE_ID` | integer | `256` |  |
| `GAMEND_LIMITS_MAX_DISPLAY_NAME` | integer | `80` |  |
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
| `GAMEND_LIMITS_MAX_NOTIFICATIONS_PER_USER` | integer | `500` |  |
| `GAMEND_LIMITS_MAX_NOTIFICATION_CONTENT` | integer | `10000` |  |
| `GAMEND_LIMITS_MAX_NOTIFICATION_TITLE` | integer | `255` |  |
| `GAMEND_LIMITS_MAX_OBJECTIVES_PER_QUEST` | integer | `10` |  |
| `GAMEND_LIMITS_MAX_PAGE_SIZE` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_PARTY_PENDING_INVITES` | integer | `20` |  |
| `GAMEND_LIMITS_MAX_PARTY_SIZE` | integer | `32` |  |
| `GAMEND_LIMITS_MAX_PENDING_FRIEND_REQUESTS` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_PROFILE_URL` | integer | `512` |  |
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
| `GAMEND_LIMITS_MAX_SOCKETS_PER_USER` | integer | `20` | Concurrent sockets per user. 0 disables; counted per app instance. |
| `GAMEND_LIMITS_MAX_TOURNAMENT_BRACKET_SIZE` | integer | `256` |  |
| `GAMEND_LIMITS_MAX_TOURNAMENT_DESCRIPTION` | integer | `1000` |  |
| `GAMEND_LIMITS_MAX_TOURNAMENT_ENTRIES` | integer | `10000` | Hard cap on a tournament's own max_entries setting. |
| `GAMEND_LIMITS_MAX_TOURNAMENT_SLUG` | integer | `100` |  |
| `GAMEND_LIMITS_MAX_TOURNAMENT_TITLE` | integer | `255` |  |
| `GAMEND_LIMITS_MAX_UPLOAD_BYTES` | integer | `5242880` | Max size of a single uploaded object (avatars/UGC). 5 MiB. |
| `GAMEND_LIMITS_MAX_USERNAME` | integer | `32` |  |
| `GAMEND_LIMITS_MIN_USERNAME` | integer | `3` |  |
| `GAMEND_LIMITS_READY_CHECK_TIMEOUT_MS` | integer | `15000` | Default answering window. Overridable per check by the caller. |


## Lobby snapshots

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_LOBBY_SNAPSHOTS_ENABLED` | boolean | `false` | Record a durable per-run snapshot of lobby state, browsable at /admin/lobby_snapshots. |
| `GAMEND_LOBBY_SNAPSHOTS_MAX_KV_ENTRIES` | integer | `200` | Cap on KV entries captured per snapshot. |
| `GAMEND_LOBBY_SNAPSHOTS_USER_KV_KEYS` | list | `` | User-scoped KV keys to capture. Empty captures none — the widest exposure in a snapshot. |


## Email

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_MAIL_SMTP_FROM_EMAIL` | string | - |  |
| `GAMEND_MAIL_SMTP_FROM_NAME` | string | `"Game Server"` |  |
| `GAMEND_MAIL_SMTP_PASSWORD` | string | - | SMTP password, or the provider's API key. Warns when unset. Secret - never log or commit it. |
| `GAMEND_MAIL_SMTP_PORT` | integer | `465` |  |
| `GAMEND_MAIL_SMTP_RELAY` | string | - | SMTP host, e.g. smtp.resend.com. Warns when unset. |
| `GAMEND_MAIL_SMTP_SNI` | string | - | TLS server name indication. Defaults to the relay host. |
| `GAMEND_MAIL_SMTP_SSL` | boolean | `true` |  |
| `GAMEND_MAIL_SMTP_TLS` | atom | `:never` | STARTTLS policy: never \| if_available \| always. |
| `GAMEND_MAIL_SMTP_USERNAME` | string | - | Warns when unset. |


## OAuth providers

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_OAUTH_APPLE_CLIENT_ID` | string | - | Services id (web audience) for Sign in with Apple. Warns when unset. |
| `GAMEND_OAUTH_APPLE_IOS_CLIENT_ID` | string | - | Bundle id (iOS audience) used when verifying Apple ID tokens. |
| `GAMEND_OAUTH_APPLE_KEY_ID` | string | - | Key id of the Sign in with Apple auth key (Apple Developer -> Keys). Warns when unset. |
| `GAMEND_OAUTH_APPLE_PRIVATE_KEY` | string | - | Contents of the Sign in with Apple .p8 key. Warns when unset. Secret - never log or commit it. |
| `GAMEND_OAUTH_APPLE_TEAM_ID` | string | - | Warns when unset. |
| `GAMEND_OAUTH_DISCORD_CLIENT_ID` | string | - | Warns when unset. |
| `GAMEND_OAUTH_DISCORD_CLIENT_SECRET` | string | - | Warns when unset. Secret - never log or commit it. |
| `GAMEND_OAUTH_FACEBOOK_CLIENT_ID` | string | - | Warns when unset. |
| `GAMEND_OAUTH_FACEBOOK_CLIENT_SECRET` | string | - | Warns when unset. Secret - never log or commit it. |
| `GAMEND_OAUTH_GOOGLE_CLIENT_ID` | string | - | Warns when unset. |
| `GAMEND_OAUTH_GOOGLE_CLIENT_SECRET` | string | - | Warns when unset. Secret - never log or commit it. |
| `GAMEND_OAUTH_GOOGLE_WEB_CLIENT_ID` | string | - | Native-app client id used to verify Google ID tokens from SDK sign-in. |
| `GAMEND_OAUTH_STEAM_API_KEY` | string | - | Steam Web API key, used for OpenID sign-in. Secret - never log or commit it. |
| `GAMEND_OAUTH_STEAM_APP_ID` | string | - |  |


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
| `GAMEND_OBSERVABILITY_METRICS_TOKEN` | string | - | When set, every non-loopback /metrics scrape must send `Authorization: Bearer <token>`. Secret - never log or commit it. |


## Payments

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_PAYMENTS_APPLE_APP_STORE_SERVER_BASE_URL` | string | - |  |
| `GAMEND_PAYMENTS_APPLE_BUNDLE_ID` | string | - | Warns when unset. |
| `GAMEND_PAYMENTS_APPLE_ISSUER_ID` | string | - | Issuer id from App Store Connect -> Users and Access -> Integrations. Warns when unset. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_APPLE_KEY_ID` | string | - | Key id of the App Store Connect API key — not the Sign in with Apple key. Warns when unset. |
| `GAMEND_PAYMENTS_APPLE_PRIVATE_KEY` | string | - | Inline .p8 contents for the App Store Connect API key. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_APPLE_PRIVATE_KEY_PATH` | string | - |  |
| `GAMEND_PAYMENTS_ENVIRONMENT` | atom | `:production` | sandbox while validating, production for real transactions. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_ACCESS_TOKEN` | string | - | Secret - never log or commit it. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_AUTO_ACKNOWLEDGE` | boolean | `false` |  |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME` | string | - | Warns when unset. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_PUBLISHER_BASE_URL` | string | - |  |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN` | string | - | Shared bearer token on the Pub/Sub push webhook. Without it the RTDN endpoint fails closed in production. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | string | - | Inline service-account JSON. Use the _PATH variant to read it from a file instead. Warns when unset. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | string | - |  |
| `GAMEND_PAYMENTS_STEAM_APP_ID` | string | - |  |
| `GAMEND_PAYMENTS_STEAM_MICROTXN_BASE_URL` | string | - |  |
| `GAMEND_PAYMENTS_STEAM_WEB_API_KEY` | string | - | Falls back to the OAuth Steam key when unset. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_API_VERSION` | string | `"2022-11-15"` |  |
| `GAMEND_PAYMENTS_STRIPE_PRODUCTION_SECRET_KEY` | string | - | sk_live_... key, used when environment is production. Warns when unset. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_PRODUCTION_WEBHOOK_SECRET` | string | - | Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_SANDBOX_SECRET_KEY` | string | - | sk_test_... key, used when environment is sandbox. Secret - never log or commit it. |
| `GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET` | string | - | Secret - never log or commit it. |


## Push notifications

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_PUSH_ADAPTER` | atom | `:auto` | Set to `log` to route every delivery to the Log provider, credentials or not. |
| `GAMEND_PUSH_APNS_ENV` | atom | `:production` | `production`, or `sandbox` for dev builds. |
| `GAMEND_PUSH_APNS_KEY_ID` | string | - | 10-character key id of the APNs auth key. Warns when unset. |
| `GAMEND_PUSH_APNS_PRIVATE_KEY` | string | - | APNs .p8 key contents, or a path to the file. Warns when unset. Secret - never log or commit it. |
| `GAMEND_PUSH_APNS_TEAM_ID` | string | - | Apple developer team id. Warns when unset. |
| `GAMEND_PUSH_APNS_TOPIC` | string | - | App bundle id, sent as apns-topic. Warns when unset. |
| `GAMEND_PUSH_FCM_CREDENTIALS` | string | - | FCM service-account JSON, inline or a path to the file. Secret - never log or commit it. |
| `GAMEND_PUSH_FCM_PROJECT_ID` | string | - | Defaults to the project id inside the FCM credentials. |
| `GAMEND_PUSH_QUEUE_CONCURRENCY` | integer | `10` | Per-node concurrent deliveries on the push queue. |


## Rate limiting

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_RATELIMIT_AUTH_LIMIT` | integer | `10` | Max login/register requests per window, per IP. |
| `GAMEND_RATELIMIT_AUTH_WINDOW_MS` | integer | `60000` | Auth HTTP window, in milliseconds. |
| `GAMEND_RATELIMIT_BACKEND` | atom | `:ets` | ets (per-node counters) or redis (shared across instances). |
| `GAMEND_RATELIMIT_DC_LIMIT` | integer | `300` | Max WebRTC DataChannel messages per window, per user. |
| `GAMEND_RATELIMIT_DC_WINDOW_MS` | integer | `10000` | WebRTC DataChannel window, in milliseconds. |
| `GAMEND_RATELIMIT_ENABLED` | boolean | `true` | Master switch for all request/message throttling. |
| `GAMEND_RATELIMIT_GENERAL_LIMIT` | integer | `240` | Max general HTTP requests per window, per IP. |
| `GAMEND_RATELIMIT_GENERAL_WINDOW_MS` | integer | `60000` | General HTTP window, in milliseconds. |
| `GAMEND_RATELIMIT_ICE_LIMIT` | integer | `150` | Max ICE candidate messages per window, per user. |
| `GAMEND_RATELIMIT_ICE_WINDOW_MS` | integer | `30000` | ICE candidate window, in milliseconds. |
| `GAMEND_RATELIMIT_REDIS_URL` | string | - | Redis URL for shared counters. **Required in production.** |
| `GAMEND_RATELIMIT_WS_LIMIT` | integer | `60` | Max WebSocket channel messages per window, per user. |
| `GAMEND_RATELIMIT_WS_WINDOW_MS` | integer | `10000` | WebSocket window, in milliseconds. |


## Realtime

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_REALTIME_DEBOUNCE_MS` | integer | `0` | Hold outbound state updates this long and push only the latest per object. 0 pushes immediately. |


## Retention

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES` | integer | `15` | Delete lobbies nobody has been seen in for N minutes. 0 disables. |
| `GAMEND_RETENTION_CHAT_MESSAGES_DAYS` | integer | `0` | Delete chat messages older than N days. 0 keeps forever. |
| `GAMEND_RETENTION_INVITES_DAYS` | integer | `30` | Delete resolved invites and join requests N days after resolution. |
| `GAMEND_RETENTION_LEDGER_DAYS` | integer | `0` | Delete wallet/inventory ledger entries older than N days. 0 keeps forever. |
| `GAMEND_RETENTION_LOBBY_SNAPSHOTS_DAYS` | integer | `30` | Delete lobby snapshots, events and blobs older than N days. |
| `GAMEND_RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` | integer | `90` | Longer window for snapshots of runs flagged anomalous. |
| `GAMEND_RETENTION_MATCHMAKING_TICKETS_HOURS` | integer | `24` | Delete matchmaking tickets older than N hours, in any status. |
| `GAMEND_RETENTION_NOTIFICATIONS_DAYS` | integer | `0` | Delete notifications older than N days. 0 keeps forever. |
| `GAMEND_RETENTION_PAYMENT_EVENTS_DAYS` | integer | `0` | Delete payment provider webhook events older than N days. Purchases are never pruned. |
| `GAMEND_RETENTION_PUSH_TOKENS_DAYS` | integer | `270` | Delete push tokens untouched for N days. Defaults to Google's stale-token guidance. |
| `GAMEND_RETENTION_TOURNAMENTS_DAYS` | integer | `0` | Delete finished tournaments older than N days. 0 keeps forever. |


## Storage

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_STORAGE_ACCESS_KEY_ID` | string | - | **Required in production.** Secret - never log or commit it. |
| `GAMEND_STORAGE_ADAPTER` | atom | `:local` | Backend for avatars and uploads: local \| s3 (any S3-compatible service). |
| `GAMEND_STORAGE_BUCKET` | string | - | **Required in production.** |
| `GAMEND_STORAGE_DIR` | string | `"priv/storage"` | Directory the local adapter writes objects to. |
| `GAMEND_STORAGE_ENDPOINT` | string | - | Custom endpoint, e.g. https://<account>.r2.cloudflarestorage.com. |
| `GAMEND_STORAGE_PUBLIC_URL` | string | - | CDN or base URL serving stored objects, whichever backend is behind it. |
| `GAMEND_STORAGE_REGION` | string | `"auto"` | Region, or "auto" for services that do not use one (R2, MinIO). |
| `GAMEND_STORAGE_SECRET_ACCESS_KEY` | string | - | **Required in production.** Secret - never log or commit it. |


## TLS & certificates

| Variable | Type | Default | Notes |
|---|---|---|---|
| `GAMEND_TLS_ACME_WEBROOT` | string | - | Webroot for Let's Encrypt HTTP-01 challenge files. Defaults to /var/www/acme. |
| `GAMEND_TLS_CERTFILE` | string | - | Path to fullchain.pem (certificate + CA chain). Warns when unset. |
| `GAMEND_TLS_FORCE` | boolean | - | Redirect HTTP to HTTPS and send HSTS. Defaults to on once certs are readable. |
| `GAMEND_TLS_KEYFILE` | string | - | Path to privkey.pem. Warns when unset. |
| `GAMEND_TLS_PORT` | integer | `443` | HTTPS listen port. |

