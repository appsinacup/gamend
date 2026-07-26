# Settings: one declared config surface

Design spec. Replaces the scattered env-var reads with a single declarative
settings layer that core, hosts and plugins all register into, and renames every
variable we own onto one derived naming convention.

Goal: one place that lists every setting the server has — its type, default,
group, whether it is required, and where its current value came from — with the
env var name **derived** from the declaration rather than written by hand.

## Where we are

Config reaches the running server through five unrelated mechanisms:

1. **`config/host_runtime.exs`** (824 lines, 64 `System.get_env` calls) — the
   env → `Application` config translation layer.
2. **`GameServer.Limits`** — `@defaults` map, overridable via
   `config :game_server_core, GameServer.Limits, ...`, read through `get/1`.
   Its 59 `LIMIT_*` env vars are **derived** from `defaults()`, not hand-listed.
3. **`GameServer.Config`** — typed reads of plugin-declared vars, with defaults
   and type inference (`env_vars/0` → `Declarations.env_vars/0`).
4. **`GameServer.Env`** — `bool/2`, `integer/2`, `log_level/2` parse helpers.
5. **~60 bare `System.get_env` calls in business logic** that bypass
   `Application` config entirely.

`Limits` is already the shape this spec generalises. Everything else is the gap.

## The gaps

**Downstream hosts maintain a forked copy of the translation layer.**
`gamend_polyglot/config/host_runtime.exs` differs from this repo's by **361
lines** — it is missing the entire object-storage block and its `LIMIT_*` list
is a stale hand-written array of 31 keys against core's 59. Its own comment
records the failure mode:

> the block core shipped never reached us and `LOBBY_SNAPSHOTS_ENABLED` did
> nothing at all

A key declared in a module with a compiled default has nothing to translate, so
this class of bug disappears.

**Nothing declares the settings, so the admin page reverse-engineers them.**
`runtime_introspection.ex:198` builds its list by regex-scraping the *source
text* of `config/host_runtime.exs` and parsing `.env.example` prose, with a
comment admitting why: "so the list stays complete even when `.env.example`
hasn't caught up".

**31 vars are read by code and documented nowhere** — `PORT`, `POOL_SIZE`, all
four `DB_*`, four `SQLITE_*`, `SSL_CERTFILE`, `SSL_KEYFILE`, `FORCE_SSL`,
`HTTPS_PORT`, `ACME_WEBROOT`, `GUARDIAN_SECRET_KEY`, `ACCESS_LOG_LEVEL`,
`REDIS_URL`, `SMTP_SNI`, `GEOIP_DB_PATH`, `APP_VERSION`, `DATABASE_ADAPTER`,
`LOBBY_SNAPSHOTS_MAX_KV_ENTRIES` — despite CONTRIBUTING requiring it.

**Two names collide on two different credentials.** `APPLE_KEY_ID` and
`APPLE_PRIVATE_KEY` are read by Sign in with Apple (`apple.ex:45`, key from
Apple Developer → Keys) *and* by the App Store Server API
(`payments/providers/apple.ex:232`, key from App Store Connect → Integrations).
A deployment using both features cannot configure both. `.env.example`
documents the name twice with conflicting descriptions.

**Four modules independently grew an env↔config fallback, in opposite
directions**: payments providers do `System.get_env(k) || Application.get_env(k)`,
while `auth_controller.ex:651` does `cfg[:client_id] || System.get_env(...)`.

## Architecture

### One provider macro

Core, hosts and plugins register identically:

```elixir
defmodule GameServer.Retention do
  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :retention,
    label: "Retention"

  setting :chat_messages_days, :integer, default: 0,
    doc: "Delete chat messages older than N days. 0 keeps forever."
  setting :push_tokens_days, :integer, default: 270
  setting :ended_lobby_minutes, :integer, default: 15
end
```

```elixir
defmodule PolyglotHook do
  use GameServer.Settings.Provider,
    app: :polyglot_hook, root: "POLYGLOT", group: :game, label: "Polyglot"

  setting :observability, :boolean, default: false
  setting :seed_salt, :string, default: nil, secret: true
end
```

`Settings.get(:game_server_core, [:retention, :chat_messages_days])` reads
`Application.get_env` and falls back to the compiled default — the `Limits.get/1`
pattern, generalised. A host that wants plain Elixir writes
`config :game_server_core, GameServer.Retention, chat_messages_days: 90` and
never touches an env var.

### Env names are derived, never typed

    <ROOT>_<GROUP>_<KEY>

    GAMEND_RETENTION_CHAT_MESSAGES_DAYS
    GAMEND_LIMITS_MAX_METADATA_SIZE
    GAMEND_OAUTH_APPLE_KEY_ID
    GAMEND_PAYMENTS_APPLE_KEY_ID
    POLYGLOT_GAME_OBSERVABILITY

`ROOT` defaults to `GAMEND` and is per-provider. The key and its env name cannot
disagree, which by itself fixes today's `chat_messages_days` ←
`RETENTION_CHAT_DAYS` mismatch, and the Apple collision becomes structurally
impossible.

**The group is the middle segment**, so the admin grouping and the env prefix
come from one source and cannot drift. `label:` is display text only.

### Groups

`HTTP` · `TLS` · `DB` · `CACHE` · `CLUSTER` · `AUTH` · `OAUTH` · `PAYMENTS` ·
`PUSH` · `MAIL` · `STORAGE` · `RATELIMIT` · `RETENTION` · `LIMITS` · `FEATURES` ·
`REALTIME` · `OBSERVABILITY` · `CONTENT`

Plugins contribute their own group from `group:`, so polyglot's settings appear
beside core's with no wiring.

### Plugin load ordering

Plugins load at runtime via `PluginManager` (`host_supervision.ex:127`), *after*
config is resolved — which is why plugin env vars are read lazily today. On
load, `PluginManager` resolves that plugin's declared settings from the
environment and `Application.put_env`s them **unless the host already set them**.
Everything then reads `Application` config uniformly.

### What this consolidates

| Today | After |
| --- | --- |
| `Limits.@defaults` + derived `LIMIT_*` | a provider; `Limits.get/1` delegates |
| `Declarations.env_vars/0` | the same provider macro, plugin-side |
| `GameServer.Config` | `Settings.get/2` |
| `GameServer.Env` | the loader's cast functions |
| `runtime_introspection` source-scraping | `Settings.all/0` — **deleted** |
| hand-written `.env.example` | generated |
| ~60 bare `System.get_env` in business logic | `Settings.get/2` |
| `host_runtime.exs`, 824 lines | ~30 lines |

## Required vs optional

The constraint: **dev and test must start with nothing set.** They already do,
structurally — the whole requirement-bearing section of `host_runtime.exs` is
inside `if config_env() == :prod`, and dev/test carry compiled
`secret_key_base` values (`config/dev.exs:44`, `config/test.exs:59`). So the
required-set can be strict in prod at zero cost to local development.

Today exactly **three** things raise at boot, all in prod: `SECRET_KEY_BASE`,
and the two redis-backend checks (`host_runtime.exs:270`, `:567`).

### Three levels

One `required:` axis. Nothing ever *fails* outside prod.

| Level | Declared | Missing in prod | Missing in dev | Missing in test |
| --- | --- | --- | --- | --- |
| **required** | `required: :prod` | boot fails | **warns** | silent |
| **warn** | `required: :warn` | logs a warning, feature degrades | silent | silent |
| **optional** | *(omitted)* | nothing — the default applies | silent | silent |

The dev warning on a `:prod` requirement is the point of having one: it says
*"this deployment will not boot in prod"* while the developer is at the
keyboard, instead of at deploy time. It never blocks local work.

In practice it is quiet. Dev already satisfies `auth.secret_key_base` from
`config/dev.exs:44`, and the other three requirements are gated on choices a dev
environment does not usually make — so it fires exactly when someone points dev
at S3 or a redis backend and forgets the credentials, which is the case worth
catching early.

Test stays silent at every level: the suite boots hundreds of times, and a
warning per boot is noise rather than signal.

### Two gates

Orthogonal to the level: *when does the check apply at all?* Most requirements
are conditional, so a gate is the common case rather than the exception.

- `when: {[:storage, :adapter], :s3}` — only checked when a selector holds.
- `with: [:key_id, :team_id, :topic]` — **complete-or-empty**. All unset means
  "not using this feature" and is silent at any level; a partial set trips the
  declared level, because a subset always means someone meant to enable it and
  mistyped.

```elixir
setting :bucket, :string, required: :prod, when: {[:storage, :adapter], :s3}
setting :topic,  :string, required: :warn, with: [:private_key, :key_id, :team_id]
setting :region, :string, default: "auto"
```

### required — boot fails

Four, and three of them already raise today:

| Setting | Gate | Why |
| --- | --- | --- |
| `auth.secret_key_base` | — | Signs every cookie and token. Raises today. |
| `storage.s3.bucket`, `.access_key_id`, `.secret_access_key` | `when storage.adapter == :s3` | Degrading to local disk means uploads vanish on redeploy — unrecoverable, and invisible until someone goes looking for a file. |
| a redis URL | `when cache.mode == :multi and cache.l2 == :redis` | Raises today. |
| a redis URL | `when ratelimit.backend == :redis` | Raises today. |

`auth.guardian_secret_key` is **not** required — it defaults to
`secret_key_base`, which is existing behaviour worth keeping.

### warn — logs, degrades, keeps running

Every one of these is either today's exact behaviour or an improvement on
today's silence:

| Group | Members | Today |
| --- | --- | --- |
| APNs | `push.apns.private_key`, `.key_id`, `.team_id`, `.topic` | warns, falls back to Log provider — **unchanged** |
| FCM | `push.fcm.credentials` + resolvable project id | warns, falls back to Log provider — **unchanged** |
| TLS | `tls.certfile` + `.keyfile` | warns, serves HTTP — **unchanged** |
| SMTP | `mail.smtp.password` + `.relay` + `.username` | silently falls back to the local mailbox adapter |
| Each OAuth provider | `oauth.<p>.client_id` + `.client_secret` | silent; the provider just fails at use |
| Sign in with Apple | `oauth.apple.client_id`, `.team_id`, `.key_id`, `.private_key` | silent; raises at first use (`apple.ex:30`) |
| App Store Server API | `payments.apple.issuer_id`, `.key_id`, `.bundle_id`, one of `.private_key` / `.private_key_path` | silent |
| Google Play | `payments.google_play.package_name` + service-account JSON or path | silent |
| Stripe live key | `when payments.environment == :production` | silent |

So this spec **makes nothing stricter than it is today** — the three things that
raise still raise, the three that warn still warn, and the six that are silent
become visible. A partial set is what trips a warn, so an operator who never
touched push, TLS or payments sees nothing.

TLS keeps its separate *file-existence* degradation: names present but the certs
not yet on disk still logs and serves HTTP, so certbot can bootstrap.
Complete-or-empty applies to the names, not the files.

### optional — everything else

All 52 limits, all retention windows, the rate-limit windows, feature flags,
cache tuning, log levels, DB pool tuning. Every one has a default; a missing
value is a normal state, not an event.

Opt-in features that are simply off when unconfigured — lobby snapshots, GeoIP,
Grafana, each push and payments provider — stay optional and announce their
resolved state in the existing `log_startup_resources/0` report, which is where
an operator already looks to see what came up.

## The rename

Every variable **we own** is renamed onto the derived convention — 191 of 203.
No aliases, no fallbacks, no compatibility period.

### Inherited names (12) — kept, declared with an explicit `env:`, marked `external: true`

`PORT` · `DATABASE_URL` · `REDIS_URL` · `MIX_ENV` · `PATH` · `ERL_AFLAGS` ·
`RELEASE_DISTRIBUTION` · `RELEASE_NODE` · `RELEASE_COOKIE` · `FLY_APP_NAME` ·
`FLY_PRIVATE_IP` · `FLY_REGION`

Other software defines these. `PORT` is injected by every PaaS; `RELEASE_*` and
`ERL_AFLAGS` are read by the BEAM. (This project has no `mix release` today —
`Dockerfile:71` runs `mix phx.server` — so `RELEASE_*` is currently read only by
the admin display. They stay reserved regardless.)

The admin viewer files these under **Inherited** rather than implying we own
them.

### Mapping

`LIMIT_*` (52) and `RETENTION_*` (11) are already regular:
`LIMIT_<X>` → `GAMEND_LIMITS_<X>`, `RETENTION_<X>` → `GAMEND_RETENTION_<X>`,
with the one correction `RETENTION_CHAT_DAYS` → `GAMEND_RETENTION_CHAT_MESSAGES_DAYS`.

The rest, by group:

| Old | New |
| --- | --- |
| `PHX_HOST`, `PHX_SCHEME`, `HOSTNAME`, `PHX_ALLOWED_ORIGINS` | `GAMEND_HTTP_HOST`, `_SCHEME`, (dropped, dup of HOST), `_ALLOWED_ORIGINS` |
| `PHX_SERVER` | `GAMEND_HTTP_SERVER` |
| `SSL_CERTFILE`, `SSL_KEYFILE`, `HTTPS_PORT`, `FORCE_SSL`, `ACME_WEBROOT` | `GAMEND_TLS_CERTFILE`, `_KEYFILE`, `_PORT`, `_FORCE`, `_ACME_WEBROOT` |
| `DATABASE_ADAPTER`, `POOL_SIZE`, `DB_POOL_TIMEOUT`, `DB_QUEUE_TARGET`, `DB_QUEUE_INTERVAL`, `DB_QUERY_TIMEOUT`, `ECTO_IPV6` | `GAMEND_DB_ADAPTER`, `_POOL_SIZE`, `_POOL_TIMEOUT`, `_QUEUE_TARGET`, `_QUEUE_INTERVAL`, `_QUERY_TIMEOUT`, `_IPV6` |
| `POSTGRES_*` (5) | `GAMEND_DB_POSTGRES_*` |
| `SQLITE_*` (5) | `GAMEND_DB_SQLITE_*` |
| `CACHE_ENABLED`, `CACHE_MODE`, `CACHE_L2`, `CACHE_REDIS_URL`, `CACHE_REDIS_POOL_SIZE` | `GAMEND_CACHE_ENABLED`, `_MODE`, `_L2`, `_REDIS_URL`, `_REDIS_POOL_SIZE` |
| `DNS_CLUSTER_QUERY` | `GAMEND_CLUSTER_DNS_QUERY` |
| `SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY`, `DEVICE_AUTH_ENABLED`, `REQUIRE_ACCOUNT_ACTIVATION`, `MIN_PASSWORD_LENGTH` | `GAMEND_AUTH_SECRET_KEY_BASE`, `_GUARDIAN_SECRET_KEY`, `_DEVICE_ENABLED`, `_REQUIRE_ACTIVATION`, `_MIN_PASSWORD_LENGTH` |
| `DISCORD_*`, `FACEBOOK_*`, `GOOGLE_CLIENT_*`, `GOOGLE_WEB_CLIENT_ID` | `GAMEND_OAUTH_DISCORD_*`, `_FACEBOOK_*`, `_GOOGLE_*` |
| `APPLE_CLIENT_ID`, `APPLE_WEB_CLIENT_ID`, `APPLE_IOS_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | `GAMEND_OAUTH_APPLE_CLIENT_ID`, `_WEB_CLIENT_ID`, `_IOS_CLIENT_ID`, `_TEAM_ID`, `_KEY_ID`, `_PRIVATE_KEY` |
| `STEAM_API_KEY`, `STEAM_APP_ID` | `GAMEND_OAUTH_STEAM_API_KEY`, `GAMEND_OAUTH_STEAM_APP_ID` |
| `PAYMENTS_ENVIRONMENT`, `STRIPE_*` (5) | `GAMEND_PAYMENTS_ENVIRONMENT`, `GAMEND_PAYMENTS_STRIPE_*` |
| `GOOGLE_PLAY_*` (5) | `GAMEND_PAYMENTS_GOOGLE_PLAY_*` |
| `APPLE_BUNDLE_ID`, `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_PRIVATE_KEY_PATH` | `GAMEND_PAYMENTS_APPLE_BUNDLE_ID`, `_ISSUER_ID`, `_KEY_ID`, `_PRIVATE_KEY`, `_PRIVATE_KEY_PATH` |
| `STEAM_WEB_API_KEY` | `GAMEND_PAYMENTS_STEAM_WEB_API_KEY` |
| `PUSH_ADAPTER`, `PUSH_QUEUE_CONCURRENCY`, `PUSH_FCM_*` | `GAMEND_PUSH_ADAPTER`, `_QUEUE_CONCURRENCY`, `_FCM_*` |
| `APNS_*` (5) | `GAMEND_PUSH_APNS_*` |
| `SMTP_*` (9) | `GAMEND_MAIL_SMTP_*` |
| `STORAGE_ADAPTER`, `STORAGE_LOCAL_DIR`, `STORAGE_PUBLIC_URL`, `STORAGE_S3_*` (5) | `GAMEND_STORAGE_ADAPTER`, `_LOCAL_DIR`, `_PUBLIC_URL`, `_S3_*` |
| `RATE_LIMIT_BACKEND`, `RATE_LIMIT_REDIS_URL` | `GAMEND_RATELIMIT_BACKEND`, `_REDIS_URL` |
| `RATE_LIMIT_HTTP_*` (4), `RATE_LIMIT_WS_*` (2), `RATE_LIMIT_WEBRTC_*` (2) | `GAMEND_RATELIMIT_HTTP_*`, `_WS_*`, `_WEBRTC_*` (config key `dc_limit` renamed to `webrtc_limit` to match) |
| `LIST_*_ENABLED` (6), `OPENAPI_ENABLED` | `GAMEND_FEATURES_LIST_*_ENABLED`, `GAMEND_FEATURES_OPENAPI_ENABLED` |
| `REALTIME_DEBOUNCE_MS` | `GAMEND_REALTIME_DEBOUNCE_MS` |
| `LOG_LEVEL`, `ACCESS_LOG_LEVEL`, `LOG_FILE_*` (4) | `GAMEND_OBSERVABILITY_LOG_LEVEL`, `_ACCESS_LOG_LEVEL`, `_LOG_FILE_*` |
| `METRICS_AUTH_TOKEN`, `GRAFANA_PUBLIC_URL` | `GAMEND_OBSERVABILITY_METRICS_TOKEN`, `_GRAFANA_URL` |
| `LOBBY_SNAPSHOTS_*` (3) | `GAMEND_OBSERVABILITY_LOBBY_SNAPSHOTS_*` |
| `THEME_CONFIG`, `GAME_SERVER_PLUGINS_DIR`, `GEOIP_DB_PATH`, `APP_VERSION` | `GAMEND_CONTENT_THEME_CONFIG`, `_PLUGINS_DIR`, `_GEOIP_DB_PATH`, `_APP_VERSION` |

`HOSTNAME` is dropped — `admin_live/config.ex:1683` reads it as a synonym for
`PHX_HOST`, and it collides with the shell's own `HOSTNAME`.

### Blast radius

**91 files**: 66 in this repo, 19 in `gamend_polyglot`, 6 in `gamend_starter`.
Plus each repo's untracked `.env`, `docker-compose*.yml`, `fly.toml`, and the
`Dockerfile` build args (`DATABASE_ADAPTER`, `GAME_SERVER_PLUGINS_DIR`,
`APP_VERSION`).

`mix gamend.settings.migrate_env <path>` rewrites a `.env` mechanically. The
only entry needing human judgement is `APPLE_KEY_ID` / `APPLE_PRIVATE_KEY`,
which map to two different targets; the task prints both and leaves them
commented.

## Admin viewer

`admin_live/settings.ex`, replacing the hand-written env sections of
`admin_live/config.ex` (2837 lines, 88 `System.get_env` calls) and the
`runtime_introspection` env-var scraping.

Rendered from `Settings.all/0`, grouped by group, showing per setting: name,
derived env var, type, default, **effective value**, **source** (`default` /
`config` / `env`), level (required / warn / optional), its gate if it has one,
and whether it is satisfied. Secrets masked. Inherited names in their own
section. Filter by group and by level; search across name, env var and doc.

`/admin` gains a card counting **unsatisfied warns** — the number that matters
at a glance, since unsatisfied *required* settings can't reach a running server.
It is the standing answer to "is anything half-configured?", which today is only
visible if someone reads the boot log at the right moment.

## Downstream

`gamend_starter` and `gamend_polyglot` lose their forked runtime config
entirely. Each `config/runtime.exs` becomes:

```elixir
import Config

for {app, module, opts} <- GameServer.Settings.from_env() do
  config app, module, opts
end

# host-specific config below
```

(Settings span `:game_server_core` and `:game_server_web`, so `from_env/0`
returns `{app, module, opts}` triples rather than one app's keyword list.)

Polyglot additionally drops its `POLYGLOT_OBSERVABILITY` translation block
(three places for one setting today: an `env_vars/0` declaration, a
`System.get_env` read, and a bespoke `config :polyglot_hook` block) down to one
`setting` line, and renames its five `POLYGLOT_*` vars onto the convention.

## Phasing

All four phases are implemented. Status as built:

| Phase | What | Done |
| --- | --- | --- |
| 1 | `Settings` + `Provider` macro, 18 groups, three levels + gates. Every core section declared; `.env.example` generated; `admin_live/settings.ex`; `runtime_introspection` scraping deleted. | Yes |
| 2 | Names derive (`GAMEND_<GROUP>_<KEY>`); ~90 business-logic `System.get_env` reads migrated; `host_runtime.exs` down to zero raw env reads; the Apple credential split. | Yes |
| 3 | `gamend_starter` and `gamend_polyglot` on the thin `runtime.exs`; polyglot's plugin converted to the provider; `.env`, compose, fly and Dockerfile renamed in both. | Yes |
| 4 | The 31 undocumented vars fold in for free (generated); docs, CONTRIBUTING and CHANGELOG updated. | Yes |

Counts as built: **218 settings across 18 groups**, 15 inherited names kept,
`host_runtime.exs` from 824 lines to 218 (the rest is derivation — endpoint,
Repo, cache levels, Pigeon and Swoosh config — which turns settings into the
shapes those libraries expect).

`GameServer.Env` is deleted — `Settings.cast/2` replaced it, and removing it
surfaced one last undeclared variable (`MAILBOX_PREVIEW_ENABLED`, now
`features.mailbox_preview`). `GameServer.Config` stays for `infer_type/1`,
which the plugin declaration registry still uses.

`gamend_starter` resolves `game_server_core` as a GitHub dependency, so its
updated code and config could not be compiled locally; every changed file
syntax-checks and no removed API is referenced, but it needs this repo pushed
before it can actually be built.

## Deferred / rejected

- **Boot-time retired-name detector: rejected.** Considered because a missed
  rename reverts silently to a default rather than erroring — `LIST_USERS_ENABLED=false`
  becoming `true` re-exposes a deliberately closed endpoint. Rejected as a
  backwards-compatibility mechanism; the admin viewer, the required-set and the
  `[breaking]` CHANGELOG entry carry it instead.
- **JSON config file: rejected.** An env layer *and* a file layer means two
  homes per key and a precedence rule to debug. A host that wants JSON writes
  five lines in its own `runtime.exs` feeding the same `Application` config —
  one destination, host's choice of input.
- **DB-backed settings: out of scope.** `config/runtime.exs` resolves before
  `GameServer.Repo` starts (`host_supervision.ex:82`), so most settings
  categorically cannot come from the database. The live-editable subset could
  later follow the `IpBanSync` pattern (DB → ETS + PubSub); client-facing values
  belong in [webhooks-remote-config.md](webhooks-remote-config.md) Part 2.
- **Renaming `PORT` to `GAMEND_HTTP_PORT` with `PORT` as fallback: rejected.**
  Reintroduces two sources for one key.

## Definition of done (CONTRIBUTING)

- [x] `GameServer.Settings` + `Settings.Provider` in `game_server_core`; every
      core section converted; `Limits.get/1` delegates without changing callers.
- [x] Env names derived; no hand-written name except the 12 inherited.
- [x] Three levels (`required: :prod` / `:warn` / omitted) with the `when:` and
      `with:` gates, evaluated once at boot with actionable messages; nothing
      enforced outside prod; dev and test start with an empty environment.
- [x] No setting is stricter than today: the three current raises still raise,
      the three current warns still warn.
- [x] Plugin settings registered on `PluginManager` load, host config winning.
- [x] ~60 business-logic `System.get_env` calls migrated to `Settings.get/2`;
      `GameServer.Config` and `GameServer.Env` folded in.
- [x] `host_runtime.exs` under ~30 lines; starter and polyglot on the thin
      `runtime.exs`.
- [x] `.env.example` generated, plus a Settings guide at
      `priv/docs/60-operations/40-settings.md`; both regenerated by `precommit`
      and `--check`ed in CI. The guide is core-only: it skips any host with no
      `priv/docs` tree rather than creating one, so a game built on this server
      gets the generated `.env.example` and none of the docs page. No
      `migrate_env` task — that belonged to the retired-name detector, which
      this spec rejects.
- [x] `admin_live/settings.ex` + `/admin` card + route + nav +
      `admin_pages_render_test`; `runtime_introspection` scraping deleted.
- [x] Docs: deployment / scaling / cache_setup / email_setup / payments /
      push_notifications / apple_sign_in pages updated to the new names;
      CONTRIBUTING's "document new env vars" item replaced with "declare a
      setting"; CHANGELOG `[breaking]`.
- [x] Tests: derivation, precedence, each required state, secret masking,
      plugin registration, viewer rendering; both adapters.
- [x] `settings_coverage_test.exs` generates **one test per declared setting**
      (218 of them) plus five integrity checks: unique variable names, every
      name derives from its group and key, only the inherited 15 opt out,
      defaults type-check, and every value round-trips
      environment → `from_env/0` → `get/2` → `resolve/0`. This is what a
      hand-written per-setting suite would give, without needing to be
      hand-written — and it caught 24 declarations the rename script missed,
      including `STEAM_APP_ID` claimed by two groups at once.
- [x] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
