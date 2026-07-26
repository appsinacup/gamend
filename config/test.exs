import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
# Use PostgreSQL if environment variables are set, otherwise use SQLite
if System.get_env("GAMEND_DB_URL") ||
     (System.get_env("GAMEND_DB_POSTGRES_HOST") && System.get_env("GAMEND_DB_POSTGRES_USER")) do
  # Use PostgreSQL when configured
  database_url =
    System.get_env("GAMEND_DB_URL") ||
      "ecto://#{System.get_env("GAMEND_DB_POSTGRES_USER")}:#{System.get_env("GAMEND_DB_POSTGRES_PASSWORD")}@#{System.get_env("GAMEND_DB_POSTGRES_HOST")}:#{System.get_env("GAMEND_DB_POSTGRES_PORT", "5432")}/#{System.get_env("GAMEND_DB_POSTGRES_DB", "game_server_test")}"

  config :game_server_core, GameServer.Repo,
    url: database_url,
    adapter: Ecto.Adapters.Postgres,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2,
    pool_timeout: 10_000,
    queue_target: 10_000,
    queue_interval: 1_000,
    timeout: 15_000
else
  # Fallback to SQLite when no PostgreSQL config
  database_path =
    Path.expand(
      "../db/game_server_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      __DIR__
    )

  File.mkdir_p!(Path.dirname(database_path))

  config :game_server_core, GameServer.Repo,
    database: database_path,
    adapter: Ecto.Adapters.SQLite3,
    pool: Ecto.Adapters.SQL.Sandbox,
    # 2, not 1: Oban runs a boot-time `verify_migrated!` query in test mode, and
    # the host tree's periodic DB workers can hold the single connection long
    # enough to starve it. The spare connection lets Oban boot.
    pool_size: 2,
    pool_timeout: 10_000,
    queue_target: 10_000,
    queue_interval: 1_000,
    timeout: 15_000,
    pragmas: [
      foreign_keys: :on,
      journal_mode: :wal,
      synchronous: :normal,
      temp_store: :memory,
      busy_timeout: 10_000
    ]
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :game_server_web, GameServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1",
  server: false

# In test we don't send emails
config :game_server_core, GameServer.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Run GameServer.Async side effects inline so assertions observe them without
# racing, and so a task can't outlive the test's DB sandbox owner.
config :game_server_core, async_inline: true

# The periodic tournament tick has no sandbox connection in tests; leave the
# ticker supervised but idle. Tests drive GameServer.Tournaments.tick/0 directly.
config :game_server_core, GameServer.Tournaments.Ticker, enabled: false

# Same for the matchmaking sweep: no sandbox connection, and on SQLite it
# collides with the test's open write transaction ("database is locked").
# Tests drive GameServer.Matchmaking.Worker.sweep/0 directly.
config :game_server_core, GameServer.Matchmaking.Worker, enabled: false

# Disable app-level caching in tests to avoid stale reads across assertions.
# Still provide the multilevel configuration so the cache can start.
config :game_server_core, GameServer.Cache,
  bypass_mode: true,
  inclusion_policy: :inclusive,
  levels: [
    {GameServer.Cache.L1, []}
  ]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure Guardian for testing
config :game_server_web, GameServerWeb.Auth.Guardian,
  issuer: "game_server",
  secret_key: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1",
  ttl: {15, :minutes}

# Disable rate limiting in tests
config :game_server_web, GameServerWeb.Plugs.RateLimiter, enabled: false

# Background presence sweeping fights with sandbox ownership in tests and can
# keep logging after the test task itself is done.
config :game_server_core, GameServer.Accounts.StalePresenceSweeper, enabled: false

# Jobs run inline on demand in tests (no queues/plugins/cron); assert with
# Oban.Testing helpers and drain explicitly. Keeps the Cron tick from firing
# against the Sandbox.
config :game_server_core, Oban, testing: :manual

# The declared setting, not just the endpoint's copy: GameServer.Settings
# validates `auth.secret_key_base` at boot, and dev should not warn about a
# secret it demonstrably has.
config :game_server_core, GameServer.Accounts,
  secret_key_base: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1"
