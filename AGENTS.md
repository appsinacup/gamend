# AGENTS.md

Gamend is an open-source game backend: an Elixir/Phoenix umbrella with
`apps/gamend_core` (domain), `apps/gamend_web` (reusable web library) and the
runnable host app at the repository root.

## Docs map

| Doc | Read it when |
|---|---|
| [README.md](README.md) | first run, prerequisites, Docker, the feature list |
| [CONTRIBUTING.md](CONTRIBUTING.md) | adding or changing a feature: data model, time, locks, hooks, SDK, web, admin, tests, i18n, finish checklist |
| [RULES.md](RULES.md) | touching UI: contrast, font sizes, radii, motion, accessible names |
| [AUDIT.md](AUDIT.md) | security or correctness work: the September 2026 audit, what was fixed and which behaviour changed on purpose |
| [ROADMAP.md](ROADMAP.md) | checking what is planned. Rendered at `/roadmap` |
| [CHANGELOG.md](CHANGELOG.md) | recording a change. Rendered at `/changelog` |
| [docs/specs/](docs/specs/README.md) | designing a planned feature. [api-conventions.md](docs/specs/api-conventions.md) is the API rulebook `mix gamend.api.lint` enforces |
| [priv/docs/](priv/docs/) | how a shipped feature behaves: its API, realtime events and hooks. The public guides at `/docs/<slug>`, one markdown file each |

## Project guidelines

- Run `mix precommit` when done and fix what it reports. It compiles with `--warnings-as-errors`, formats, regenerates the SDK and settings docs, extracts theme strings, runs `test`, `credo --strict` and `gamend.api.lint`, and repeats the compile/format/credo steps in `apps/gamend_core` and `apps/gamend_web` (plus `format` in plugins, `sdk` and `sdk_tools`). CI also runs dialyzer and `deps.audit`.
- Use `:req` (`Req`) for HTTP. **Avoid** `:httpoison`, `:tesla` and `:httpc`.
- Declare settings with `Gamend.Settings.Provider`; never read `System.get_env/1`. The env var name derives from the declaration: `GAMEND_<GROUP>_<NAME>` (`GAMEND_DB_URL`, `GAMEND_LIMITS_MAX_PAGE_SIZE`, `GAMEND_FEATURES_LIST_QUESTS`). `.env.example` and the Settings guide are generated (`mix gamend.settings.env_example`, `mix gamend.settings.guide`).
- Update `CHANGELOG.md` for new features and for changes to config or public APIs. Format: [CONTRIBUTING.md](CONTRIBUTING.md#finish).

## Repository architecture (core/web/root host)

- `apps/gamend_core`: contexts, schemas, migrations, business logic, most mix tasks (`gen.sdk`, `gamend.api.lint`, `demo.seed`, `host.*`).
- `apps/gamend_web`: controllers, LiveViews, channels, components, JS (`apps/gamend_web/assets/js`), static assets (`apps/gamend_web/priv/static`).
- repository root (`:gamend_host`): the runnable host and the extension point for forks — router, boot config, branding, `assets/css/app.css`, `theme/config.json`, guides, gettext catalogues, `priv/static`.

### Running the app

- `mix setup` once, then `mix dev.start` (creates the DB, migrates, builds assets, runs `phx.server`).
- The endpoint module is `GamendWeb.Endpoint`; the host OTP app starts it.
- `GamendHost.Application` starts `GamendWeb.HostSupervision.children/1`. A core process goes in that list; a host-only one goes in its `:extra` option.

### Routing ownership / extension point

- Routes are macros in `GamendWeb.Router.Shared` (`apps/gamend_web/lib/gamend_web/router/shared.ex`): `gamend_pipelines/0`, `gamend_api_routes/0`, `gamend_admin_live_routes/1`, `gamend_authenticated_live_routes/2`, `gamend_current_user_routes/2`, … Add a core route inside the macro that owns its area.
- Host router: `GamendHost.Router` (`lib/gamend_host/router.ex`) calls those macros and adds host-only routes (`/sitemap.xml`, `/content/*`). `GamendWeb.Router` is core's default and calls the same macros.
- The endpoint's `dispatch_router/2` reads `Application.get_env(:gamend_web, :router, GamendWeb.Router)`, so `gamend_web` never depends on `gamend_host` at compile time. The host sets it in `config/host_config.exs` (`config :gamend_web, router: GamendHost.Router`).

Fork guidance:

- Leave a macro out of your router to drop that surface entirely; don't delete files from the dependency.
- If you *remove* upstream routes but the upstream UI still uses route helpers (`~p"..."`) pointing at `GamendWeb.Router`, you can end up generating links for routes that the host no longer serves. If you want strict route removal, forks should adjust the UI accordingly (or provide replacement routes that match the UI’s expectations).

### Stack

Elixir 1.20 / OTP 29 (`.tool-versions`), Phoenix 1.8, LiveView 1.2, Ecto 3.14, Bandit, Tailwind 4 + daisyUI 5, esbuild, Nebulex 3, Oban, Guardian (JWT), OpenApiSpex, `ex_webrtc`/`ex_sctp` (Rust NIF: local builds need `rustup`).

### Database

- SQLite by default, Postgres in production. The adapter is chosen at **compile** time: `GAMEND_DB_ADAPTER=postgres` at build. Dev/test switch to Postgres when `GAMEND_DB_URL` or `GAMEND_DB_POSTGRES_HOST` + `GAMEND_DB_POSTGRES_USER` are set; after changing them run `mix deps.clean gamend_core gamend_web --build`.
- Every migration and query must work on both adapters. Rules: [CONTRIBUTING.md](CONTRIBUTING.md#data-model-if-the-feature-stores-data).
- Schemas `use Gamend.Schema` (UUIDv7 ids).

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- `GamendWeb.Layouts` is aliased in `apps/gamend_web/lib/gamend_web.ex`, so you can use it without aliasing it again. It is a facade over `GamendWeb.HostLayouts`
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- `<.flash_group>` lives in the layout modules. You are **forbidden** from calling it outside `layouts.ex`, `host_layouts.ex` and `host_layout_shell.ex`
- `core_components.ex` provides an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for heroicons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input
- Instants render with `<.timestamp at={...} />` and are entered with `<.input type="utc-datetime-local">`. See [CONTRIBUTING.md](CONTRIBUTING.md#time)

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwind v4 has **no tailwind.config.js**. The stylesheet is the root `assets/css/app.css`, which uses the v4 import syntax:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../../apps/gamend_web/assets/js";
      @source "../../apps/gamend_web/lib";
      # plus the deps/gamend_web paths a fork resolves, ../../lib and ../../priv/docs

- **Always use and maintain this import syntax** in the app.css file
- **Never** use `@apply` when writing raw css
- daisyUI 5 is loaded as a Tailwind plugin (`assets/vendor/daisyui.js`) and the UI is built on its tokens and component classes. Follow existing pages; radii and colours come from daisyUI tokens ([RULES.md](RULES.md))
- The esbuild bundles are fixed in `config/host_config.exs`: `app.js`, `theme-init.js`, `mermaid.js` from `apps/gamend_web/assets/js`, plus the host's `assets/js/host_hooks.js`
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**. The browser CSP (`script-src 'self'`) blocks them

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions
- The accessibility floors in [RULES.md](RULES.md) are hard limits


<!-- phoenix-gen-auth-start -->
## Authentication

This application uses both session-based authentication (for browser flows) and JWT authentication (for API flows).

### Browser Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. Pipelines and `live_session` scopes are declared in `GamendWeb.Router.Shared`; the plugs and `on_mount` hooks live in `GamendWeb.UserAuth`:
  - A plug `:fetch_current_scope_for_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - A plug `:require_admin_user` for admin pages
  - A `live_session :current_user` scope (in `gamend_current_user_routes/2`) - for routes that need the current user but don't require authentication, similar to `:fetch_current_scope_for_user`
  - A `live_session :require_authenticated_user` scope (in `gamend_authenticated_live_routes/2`) - for routes that require authentication, similar to the plug with the same name
  - A `live_session :require_admin` scope (in `gamend_admin_live_routes/1`) - for `/admin` pages
  - In all cases, a `@current_scope` is assigned to the Plug connection and LiveView socket
  - The `on_mount` lists come from `GamendWeb.Router.Shared.current_user_on_mount/0`, `require_authenticated_on_mount/0` and `require_admin_on_mount/0`
- **Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**
- Contexts take a `%User{}` or a user id, not the scope: pass `current_scope.user` (or `.user.id`) and filter queries by it
- To derive/access `current_user` in templates, **always use the `@current_scope.user`**, never use **`@current_user`** in templates or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_user` can only be defined __once__ in the router, so all routes for the `live_session :current_user`  must be grouped in a single block. The macros accept a `do` block that is spliced into their `live_session`, which is how a host adds routes to one
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug and `live_session` as described below**

### Routes that require authentication

LiveViews that require login go inside the __existing__ `live_session :require_authenticated_user` block in `gamend_authenticated_live_routes/2`:

    scope "/", GamendWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: GamendWeb.Router.Shared.require_authenticated_on_mount() do
        live "/users/settings", UserLive.Settings, :edit
        live "/users/settings/confirm_email/:token", UserLive.Settings, :confirm_email
        # our own routes that require logged in user
        live "/notifications", NotificationsLive, :index
      end
    end

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", GamendWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

LiveViews that work with or without authentication go in the __existing__ `live_session :current_user` block in `gamend_current_user_routes/2`:

    scope "/", GamendWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: GamendWeb.Router.Shared.current_user_on_mount() do
        live "/leaderboards", LeaderboardsLive, :index
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
- `:api_optional_auth` loads the user when a token is present; `:api_admin` requires an admin
- Verification loads the user from the database and compares the token's `"tv"` claim against `users.token_version` — bumping the version (password change, email change, logout, `Accounts.revoke_all_tokens/1`) revokes all previously issued access and refresh tokens
- **Always** use the `:api_auth` pipeline for API routes that require authentication:

      scope "/api/v1", GamendWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/me", MeController, :show
      end

- In API controllers, access the authenticated user via `conn.assigns.current_scope.user` (Guardian pipeline sets this)
- Guardian implementation is in `apps/gamend_web/lib/gamend_web/auth/guardian.ex`
- Guardian pipeline is in `apps/gamend_web/lib/gamend_web/auth/pipeline.ex`
<!-- phoenix-gen-auth-end -->

## Domains

Each feature has a context in `apps/gamend_core/lib/gamend/` and a guide in
`priv/docs/`. The guide covers behaviour, endpoints, realtime events and
hooks; read it before changing the feature. What follows is only the
invariants code must keep.

| Context | Guide | Invariants |
|---|---|---|
| `Gamend.Accounts` | [authentication](priv/docs/20-authentication/10-authentication.md) | Split into `Accounts.*` submodules; the public API stays on `Gamend.Accounts`. Cache users only via `Accounts.cache_user/1`, never `Cache.put` the `{:accounts, :user, id}` key |
| `Gamend.Lobbies` | [lobbies](priv/docs/40-gameplay/02-lobbies.md) | One lobby per user (`users.lobby_id`). Hidden lobbies never appear in public lists. Hostless lobbies are server-managed |
| `Gamend.Parties` | [parties](priv/docs/40-gameplay/04-parties.md) | One party per user (`users.party_id`). Invite-only; only the leader steers. A party enters a lobby all or nothing |
| `Gamend.Groups` | [groups](priv/docs/40-gameplay/06-groups.md) | `public` / `private` / `hidden`. Invites in `Groups.Invites`, join requests in `Groups.JoinRequests`, re-exported from `Gamend.Groups` |
| `Gamend.Friends` | [friends](priv/docs/40-gameplay/50-friends.md) | `blocked?/2` is bidirectional. Check it (or `any_blocked?/2`) on every invite and DM |
| `Gamend.Chat` | [chat](priv/docs/40-gameplay/60-chat.md) | Types `lobby` / `group` / `party` / `friend`. Moderation (word filter, reports, mutes) lives under `Gamend.Chat.*` |
| `Gamend.Notifications` | [notifications](priv/docs/40-gameplay/70-notifications.md) | The type set is closed: `Notifications.Types` plus plugin `notification_types/0`; an unknown `metadata.type` (string or atom key) is rejected at write. A code core emits goes in `Types` and in the list in `notification_types_test.exs`. Invite records are independent of the notification they send |
| `Gamend.Push` | [push](priv/docs/40-gameplay/80-push-notifications.md) | Delivery per token (FCM / APNs) on the Oban `push` queue. No public send endpoint |
| `Gamend.Quests` | [quests](priv/docs/40-gameplay/40-quests.md) | Achievements are quests with `category: "achievement"`; there is no Achievements context. Progress is server-authoritative, rewards pay exactly once |
| `Gamend.Leaderboards` | [leaderboards](priv/docs/40-gameplay/10-leaderboards.md) | |
| `Gamend.Tournaments` | [tournaments](priv/docs/40-gameplay/20-tournaments.md) | Hooks and broadcasts wait for the commit (`Gamend.AfterCommit`); `tick/1` locks with `Lock.exclusive/3`, one transaction per tournament |
| `Gamend.Matchmaking`, `Gamend.ReadyChecks` | [matchmaking](priv/docs/40-gameplay/30-matchmaking.md) | A party queues as one unit |
| `Gamend.Economy`, `Gamend.Inventory` | [economy](priv/docs/50-monetization/05-economy.md) | Ledgered through `Gamend.Ledger`. `Economy.spend/4` is one conditional SQL statement and needs no lock |
| `Gamend.Payments` | [payments](priv/docs/50-monetization/10-payments.md) | |
| `Gamend.KV` | [key-value](priv/docs/45-storage/10-key-value.md) | Client reads pass the `before_kv_get` hook |
| `Gamend.Storage` | [object storage](priv/docs/45-storage/20-object-storage.md) | Local disk or S3. Uploads are two steps per entity (`…/upload_url`, then confirm); there is no generic upload endpoint |
| `Gamend.Retention` | [data retention](priv/docs/45-storage/30-data-retention.md) | A table that grows without bound needs a retention class, or a stated reason it is bounded |
| `Gamend.Jobs`, `Gamend.Schedule` | [background jobs](priv/docs/60-operations/45-background-jobs.md) | Oban; the engine follows the Repo adapter (Lite on SQLite) |
| `Gamend.Analytics`, `Gamend.ClientLogs`, `Gamend.LobbySnapshots` | [analytics](priv/docs/60-operations/50-player-analytics.md), [client logs](priv/docs/30-clients/60-client-logs.md), [snapshots](priv/docs/60-operations/55-lobby-snapshots.md) | |
| `Gamend.Signaling`, `Gamend.Realtime`, `Gamend.Presence` | [realtime](priv/docs/30-clients/30-realtime.md), [webrtc](priv/docs/30-clients/50-webrtc.md) | |
| `Gamend.Settings`, `Gamend.Limits`, `Gamend.Config` | [settings](priv/docs/60-operations/40-settings.md) | Size and count caps live in `Gamend.Limits` and are enforced in the changeset |
| `Gamend.Hooks` | [server scripting](priv/docs/40-gameplay/90-server-scripting.md) | See Hooks below |
| `Gamend.Content`, `Gamend.Theme` | [theme](priv/docs/10-setup/50-theme.md) | `Content` serves `CHANGELOG.md`, `ROADMAP.md`, `blog/` and `priv/docs/` (paths in `lib/gamend_host/content_paths.ex`) |

Web-side features with no context: the site search palette (`GamendWeb.SearchIndex`; host content in `lib/gamend_host/search.ex`), the sitemap (`GamendWeb.Sitemap.*`; host pages in `lib/gamend_host/sitemap/source.ex` and `sitemap_controller.ex`), IndexNow (`GamendWeb.IndexNow`), and the public feature gates (`GamendWeb.Features`, `GAMEND_FEATURES_*`).

### Hooks

- Plugins implement `Gamend.Hooks`. They load from `modules/plugins/*` (`GAMEND_CONTENT_PLUGINS_DIR`) as bundled `ebin/`; run `mix plugin.bundle` after changing one. Examples live in `modules/plugins_examples/`.
- `before_*` hooks are pipelines: return `{:ok, value}` to allow (optionally modified) or `{:error, reason}` to block. `after_*` hooks run asynchronously via `Gamend.Async.run/1`.
- **Never** dispatch a hook or broadcast inside a transaction or lock. Open transactions with `Gamend.AfterCommit.transaction/2` and broadcast with `Gamend.Broadcast.publish/2`, which wait for the commit; run a `before_*` hook before taking the lock. See [CONTRIBUTING.md](CONTRIBUTING.md#hooks-so-plugins-can-extend-the-feature).
- Adding a callback touches six places: [CONTRIBUTING.md](CONTRIBUTING.md#hooks-so-plugins-can-extend-the-feature). The full hook list is in the [server scripting guide](priv/docs/40-gameplay/90-server-scripting.md).

### PubSub & realtime

- Topics are `"resource:<id>"` for one instance and `"resources"` for the collection (`"lobby:<id>"` / `"lobbies"`, `"group:<id>"` / `"groups"`, `"party:<id>"`, `"user:<id>"`). Chat uses `"chat:lobby:<id>"`, `"chat:group:<id>"`, `"chat:party:<id>"` and `"chat:friend:<low>:<high>"` (sorted id pair).
- Socket channels are registered in `@channels` in `user_socket.ex`: `UserChannel`, `LobbyChannel`, `LobbiesChannel`, `GroupChannel`, `GroupsChannel`, `PartyChannel`, `SignalingChannel`. Every server→client event is registered in `GamendWeb.RealtimeEvents`.
- LiveViews subscribe to PubSub directly (context `subscribe_*` functions), not through channels.
- WebRTC: the server is a peer, signalled over `UserChannel` (`webrtc:*` events, one `GamendWeb.WebRTCPeer` per user); peer-to-peer rooms use `SignalingChannel` on `signaling:<lobby_id>`. Config is `config :gamend_web, :webrtc` in `config/host_config.exs`. Details: [webrtc guide](priv/docs/30-clients/50-webrtc.md).
- Event payloads and client usage: [realtime guide](priv/docs/30-clients/30-realtime.md).

### Caching conventions

- App cache is `Gamend.Cache` (Nebulex 3, multilevel: local L1 + optional Redis/partitioned L2). **Nebulex 3 returns `{:ok, value}` tuples** — use `Gamend.Cache.get!/1` (raw value, `nil` on miss), `fetch/1` or `cached/3`, never bare `get/1` compared against raw values.
- Read caching uses **version keys**: cache keys embed a `*_cache_version(...)` counter read via `get!(...) || 1`; invalidate with `Gamend.Cache.bump_version/1`, which also bumps the counter on other nodes. Data entries must carry a TTL, normally `Gamend.Cache.ttl/0` (`GAMEND_CACHE_TTL_MS`, default 60s) — that TTL is the cross-instance staleness bound.
- When a stale read would be *incorrect* (not merely briefly outdated) — cached users gating auth, sessions, tokens, KV values — invalidate with `Gamend.Cache.invalidate/1` (delete + PubSub broadcast; `Gamend.Cache.Sync` evicts the key from other instances' L1) instead of `delete/1`.

### Locks

- Any read-modify-write (capacity check before insert, merging a map) runs under `Gamend.Lock.serialize/3`. It uses `pg_advisory_xact_lock` on Postgres (behind a node-local mutex, so waiters hold no connection) and a `:global` mutex (`Gamend.Lock.Local`) on SQLite, so it holds on both.
- `serialize/3` holds a transaction for its whole function, which on SQLite is the only write lock: keep the function to database work. Hooks, hashing and HTTP calls go before it; broadcasts and tasks inside wait for the commit on their own. A job that must run once cluster-wide but writes in pieces takes `Gamend.Lock.exclusive/3` instead.
- Atom namespaces are registered in `@namespaces` in `Gamend.Repo.AdvisoryLock` (`:lobby` 1, `:group` 2, `:party` 3, `:friendship` 4, and so on through 12). Register a new one there; a string namespace needs no registration.
- Prefer an atomic write where one exists (`Economy.spend/4`).

### API shape & pagination

List endpoints take `page` / `page_size` (default 25, clamped to `max_page_size`) and return `data` plus a six-key `meta` built by `GamendWeb.Pagination`. Contexts page through `Gamend.Query` and pair each list with a `count_*`. Every response is one of four shapes — `{data}`, `{data, meta}`, `{ok: true}`, `{error, message?, errors?}` — answered through `GamendWeb.Reply` (`reply_data`, `reply_page`, `reply_ok`, `reply_error`) and `unprocessable/2`; every documented response is a named `GamendWeb.Schemas.*` module. `GamendWeb.ApiShapeTest` and `GamendWeb.ResponseContract` fail the suite otherwise (R15/R16). Everything else — ids, names, time fields, null policy, errors, paths, uploads — is in [docs/specs/api-conventions.md](docs/specs/api-conventions.md).

## Adding a feature

Follow [CONTRIBUTING.md](CONTRIBUTING.md). Where things live:

- Context: `apps/gamend_core/lib/gamend/`. Migrations: `apps/gamend_core/priv/repo/migrations/`.
- API controllers: `apps/gamend_web/lib/gamend_web/controllers/api/v1/` (admin under `admin/`), documented with OpenApiSpex `operation/2`; the spec is built from code.
- Routes: the matching macro in `router/shared.ex`.
- Admin LiveViews: `apps/gamend_web/lib/gamend_web/live/admin_live/`, routed in `gamend_admin_live_routes/1`.
- Public LiveViews: `apps/gamend_web/lib/gamend_web/live/`. Nav links: `navigation.primary_links` in `theme/config.json` and `default_primary_nav_links/0` in `host_layouts.ex`.
- Channels: `apps/gamend_web/lib/gamend_web/channels/`, registered in `@channels` in `user_socket.ex`.
- Guide: a markdown file in `priv/docs/<NN-category>/`. No registration.
- This file: update it when a convention changes.

## Project file organization

```
apps/
  gamend_core/            # contexts, schemas, migrations, core mix tasks
    lib/gamend/           # one context per feature (see Domains)
    lib/mix/tasks/        # gen.sdk, gamend.api.lint, demo.seed, gamend.settings.*, host.*
    priv/repo/migrations/
    test/                 # context tests + shared test support
  gamend_web/             # web library
    lib/gamend_web/
      controllers/api/v1/        # player API (admin/ = admin API)
      channels/                  # socket channels, WebRTC peer
      live/                      # public and player LiveViews
      live/admin_live/           # /admin console
      components/                # core_components, layouts, host_layouts*
      router/shared.ex           # route macros
      auth/                      # Guardian JWT
      sitemap/, search_index/, index_now.ex
    assets/js/            # app.js, webrtc.js, hooks
    test/                 # controller, channel, LiveView tests
lib/gamend_host/          # host: application, router, search, sitemap, page meta
lib/gamend_web/           # host's docs LiveView (HostPublicDocs), content controller
assets/                   # host app.css, host_hooks.js, vendor Tailwind plugins
config/                   # config.exs -> host_config.exs; runtime.exs -> host_runtime.exs
priv/docs/                # public guides (markdown)
priv/gettext/             # host translations
theme/config.json         # branding, navigation, pages
blog/                     # blog posts (markdown)
modules/plugins/          # loaded hook plugins; plugins_examples/ = examples
sdk/, sdk_tools/          # Elixir plugin SDK stubs; plugin.bundle and GDScript tasks
clients/                  # SDK generators and templates: JS, Godot, Balaur, C++ (sdkgen/)
proto/                    # realtime protobuf schema
stress/                   # load tests
docs/specs/               # design specs
test/                     # host tests
```

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
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`. Run it from the app that owns the test (`apps/gamend_core`, `apps/gamend_web`, or the root for host tests); root `mix test` runs all three suites
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
- For "app wide" template imports, you can import/alias into the `html_helpers` block of `apps/gamend_web/lib/gamend_web.ex`, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use GamendWeb, :html`

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
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in `apps/gamend_web/assets/js` and integrate them with its `app.js` (host-only hooks go in the root `assets/js/host_hooks.js`)

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
