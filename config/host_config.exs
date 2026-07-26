# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# In dev, load .env into the environment before anything reads System.get_env.
# This file runs at compile time, so .env can drive compile-time settings —
# most importantly the database adapter (see the Repo config in dev.exs).
if config_env() == :dev do
  Code.require_file("dotenv.exs", __DIR__)
  GameServer.Dotenv.load(Path.expand("../.env", __DIR__))
end

config :game_server_web, :scopes,
  user: [
    default: true,
    module: GameServer.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: GameServer.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :game_server_core, ecto_repos: [GameServer.Repo]
config :game_server_host, ecto_repos: [GameServer.Repo]

config :game_server_web,
  ecto_repos: [GameServer.Repo],
  generators: [timestamp_type: :utc_datetime],
  environment: config_env()

config :game_server_web,
  router: GameServerHost.Router,
  host_router: GameServerHost.Router,
  host_gettext_backend: GameServerHost.Gettext,
  home_banner_link: "/docs/setup",
  host_static_app: :game_server_host,
  asset_static_app: :game_server_host,
  well_known_static_app: :game_server_host,
  host_static_paths: ~w(images game favicon.ico robots.txt .well-known theme.css)

# MDEx's NIF only builds in the syntax highlighter when told to at compile
# time. Every root that compiles the NIF needs this - the host app, and each
# app under apps/ - or fenced code raises the moment highlighting is requested.
config :mdex_native, syntax_highlighter: :lumis

# Adapter selection (compile-time). Override with GAMEND_DB_ADAPTER=postgres
# at build time for production Postgres deployments. In dev, setting
# GAMEND_DB_POSTGRES_*/GAMEND_DB_URL (shell or .env) makes dev.exs override this with
# Postgres; after changing them, recompile:
#   mix deps.clean game_server_core game_server_web --build && mix compile
default_adapter =
  if System.get_env("GAMEND_DB_ADAPTER") == "postgres",
    do: Ecto.Adapters.Postgres,
    else: Ecto.Adapters.SQLite3

config :game_server_core, GameServer.Repo,
  adapter: default_adapter,
  # All tables use UUID (v7) primary/foreign keys — see GameServer.UUIDv7.
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Durable background jobs (GameServer.Jobs / GameServer.Schedule). The `:engine`
# (Basic on Postgres, Lite on SQLite) is injected at runtime from the Repo's
# actual adapter by GameServer.Jobs.oban_config/0 — so it stays correct when
# dev/test switch the Repo to Postgres via GAMEND_DB_POSTGRES_HOST. The single per-minute
# Cron entry drives Schedule.TickWorker (see GameServer.Schedule).
config :game_server_core, Oban,
  repo: GameServer.Repo,
  queues: [default: 10, hooks: 20, mailers: 5, storage: 5, webhooks: 10, push: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [{"* * * * *", GameServer.Schedule.TickWorker}]}
  ]

# Push notifications (GameServer.Push) need no compiled config: delivery
# routes per token off its `provider` column, and a provider whose dispatcher
# isn't running falls back to the zero-config Log provider. The PUSH_* /
# APNS_* vars (see config/host_runtime.exs) configure the dispatchers at
# runtime.

# Object storage (GameServer.Storage). Defaults to local disk; STORAGE_ADAPTER
# and the STORAGE_* vars (see config/host_runtime.exs) select and configure a
# backend at runtime.
config :game_server_core, GameServer.Storage, adapter: :local

# HTTP caching per key-prefix (first match wins). The `avatars/` immutable rule
# and the revalidate-by-ETag default ship in code; override here to add prefixes
# or change TTLs. Applied to the local serve route and set as S3 object metadata.
#
#   config :game_server_core, GameServer.Storage,
#     adapter: GameServer.Storage.Local,
#     cache_policies: [
#       {"avatars/", "public, max-age=31536000, immutable"},
#       {"public/", "public, max-age=3600"}
#     ],
#     default_cache_control: "public, max-age=0, must-revalidate"

config :ex_aws, json_codec: Jason

host_root = Path.expand("..", __DIR__)
host_theme_root = Path.join(host_root, "theme")
web_dep_root = Mix.Project.deps_paths()[:game_server_web]

web_app_root =
  cond do
    File.dir?(Path.join(host_root, "apps/game_server_web")) ->
      Path.join(host_root, "apps/game_server_web")

    is_binary(web_dep_root) && File.dir?(Path.join(web_dep_root, "apps/game_server_web")) ->
      Path.join(web_dep_root, "apps/game_server_web")

    is_binary(web_dep_root) ->
      web_dep_root

    true ->
      Path.join(host_root, "apps/game_server_web")
  end

web_assets_root = Path.join(web_app_root, "assets")
host_assets_output_root = Path.join(host_root, "priv/static/assets/js")

config :game_server_core, GameServer.Theme.JSONConfig,
  default_config_path: Path.join(host_theme_root, "config.json")

# Configures the endpoint
config :game_server_web, GameServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GameServerWeb.ErrorHTML, json: GameServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GameServer.PubSub,
  live_view: [signing_salt: "ZPmggGLv"]

# Extend Phoenix's default gzippable extensions to include Godot web export formats.
# Default list: .js .map .css .txt .text .html .json .svg .eot .ttf
# Added: .wasm .pck (binary but highly compressible, ~60-70% reduction)
# NOT added: .png (already compressed, gzip makes it larger)
config :phoenix,
  gzippable_exts: ~w(.js .map .css .txt .text .html .json .svg .eot .ttf .wasm .pck)

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :game_server_core, GameServer.Mailer, adapter: Swoosh.Adapters.Local

# Cache defaults (can be overridden in env-specific configs).
# Default to a single-level local cache for dev simplicity.
config :game_server_core, GameServer.Cache,
  inclusion_policy: :inclusive,
  levels: [
    {GameServer.Cache.L1, []}
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  game_server_web: [
    args: [
      "js/app.js",
      "js/theme-init.js",
      "js/mermaid.js",
      "--bundle",
      "--target=es2022",
      "--outdir=#{host_assets_output_root}",
      "--external:/fonts/*",
      "--external:/images/*",
      "--alias:@=."
    ],
    cd: web_assets_root,
    env: %{
      "NODE_PATH" => [
        Path.join(host_root, "deps"),
        Mix.Project.build_path(),
        Path.join(Mix.Project.build_path(), Atom.to_string(config_env()))
      ]
    }
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  game_server_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: host_root
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :order_id, :provider, :provider_reason, :purchase_id, :reason]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Filter sensitive parameters from logs
config :phoenix, :filter_parameters, ["password", "token", "secret", "authorization", "api_key"]

# Configure Guardian for JWT authentication
config :game_server_web, GameServerWeb.Auth.Guardian,
  issuer: "game_server",
  secret_key: "REPLACE_THIS_IN_RUNTIME_CONFIG"

# WebRTC DataChannel support (requires ex_webrtc + ex_sctp deps)
config :game_server_web, :webrtc,
  enabled: true,
  ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Custom MIME types for Godot web exports
config :mime, :types, %{
  "application/octet-stream" => ["pck"]
}

config :ueberauth, Ueberauth,
  providers: [
    discord: {Ueberauth.Strategy.Discord, [default_scope: "identify email"]},
    apple: {Ueberauth.Strategy.Apple, []},
    google: {Ueberauth.Strategy.Google, []},
    facebook: {Ueberauth.Strategy.Facebook, []},
    steam: {Ueberauth.Strategy.Steam, []}
  ]

# Provider credentials are not set here. Ueberauth reads them from its own
# application env, which host_runtime.exs fills from the declared
# GameServer.OAuth.Providers settings — one source, resolved at boot.
