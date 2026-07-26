import Config

if System.get_env("GAMEND_DB_URL") ||
     (System.get_env("GAMEND_DB_POSTGRES_HOST") && System.get_env("GAMEND_DB_POSTGRES_USER")) do
  database_url =
    System.get_env("GAMEND_DB_URL") ||
      "ecto://#{System.get_env("GAMEND_DB_POSTGRES_USER")}:#{System.get_env("GAMEND_DB_POSTGRES_PASSWORD")}@#{System.get_env("GAMEND_DB_POSTGRES_HOST")}:#{System.get_env("GAMEND_DB_POSTGRES_PORT", "5432")}/#{System.get_env("GAMEND_DB_POSTGRES_DB", "game_server_web_dev")}"

  config :game_server_core, GameServer.Repo,
    url: database_url,
    adapter: Ecto.Adapters.Postgres,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
else
  database_path = Path.expand("../priv/db/game_server_web_dev.db", __DIR__)
  File.mkdir_p!(Path.dirname(database_path))

  config :game_server_core, GameServer.Repo,
    database: database_path,
    adapter: Ecto.Adapters.SQLite3,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
end

config :game_server_web, GameServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "l/tTJZ4KUNjIfiUsNQDQLWOTgFlyiOz8RQ2EgSRa7mopMzPLJuu7/8s5pA7iiSgO",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:game_server_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:game_server_web, ~w(--watch)]}
  ]

config :game_server_web, GameServerWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/game_server_web/(?:controllers|live|components|router|plugs)/?.*\.(ex|heex)$"
    ]
  ]

config :game_server_web, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

# The mailer is configured by the host (config/host_runtime.exs) from the
# declared GameServer.Mail settings. This app only needs the local adapter's
# api_client off when running standalone.
config :swoosh, :api_client, false

config :game_server_web, GameServerWeb.Auth.Guardian,
  issuer: "game_server",
  secret_key: "l/tTJZ4KUNjIfiUsNQDQLWOTgFlyiOz8RQ2EgSRa7mopMzPLJuu7/8s5pA7iiSgO",
  ttl: {15, :minutes}

# The declared setting, not just the endpoint's copy: GameServer.Settings
# validates `auth.secret_key_base` at boot, and dev should not warn about a
# secret it demonstrably has.
config :game_server_core, GameServer.Accounts, secret_key_base: "l/tTJZ4KUNjIfiUsNQDQLWOTgFlyiOz8RQ2EgSRa7mopMzPLJuu7/8s5pA7iiSgO"
