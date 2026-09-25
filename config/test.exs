import Config

# Only in tests, remove the complexity from the password hashing algorithms.
# bcrypt is still reachable through PasswordHash for pre-Argon2id rows.
config :bcrypt_elixir, :log_rounds, 1

# 256 KiB / 1 pass. Argon2id at the production settings is ~24ms a hash, which
# any suite that registers users pays over and over.
config :gamend_core, Gamend.Accounts.PasswordHash,
  argon2_memory_log2: 8,
  argon2_time_cost: 1

# Configure your database
# Use PostgreSQL if environment variables are set, otherwise use SQLite
if System.get_env("GAMEND_DB_URL") ||
     (System.get_env("GAMEND_DB_POSTGRES_HOST") && System.get_env("GAMEND_DB_POSTGRES_USER")) do
  # Use PostgreSQL when configured
  database_url =
    System.get_env("GAMEND_DB_URL") ||
      "ecto://#{System.get_env("GAMEND_DB_POSTGRES_USER")}:#{System.get_env("GAMEND_DB_POSTGRES_PASSWORD")}@#{System.get_env("GAMEND_DB_POSTGRES_HOST")}:#{System.get_env("GAMEND_DB_POSTGRES_PORT", "5432")}/#{System.get_env("GAMEND_DB_POSTGRES_DB", "gamend_test")}"

  config :gamend_core, Gamend.Repo,
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

  config :gamend_core, Gamend.Repo,
    database: database_path,
    adapter: Ecto.Adapters.SQLite3,
    # Match production: see the note in config/host_runtime.exs.
    default_transaction_mode: :immediate,
    pool: Ecto.Adapters.SQL.Sandbox,
    # 2, not 1: Oban runs a boot-time `verify_migrated!` query in test mode, and
    # the host tree's periodic DB workers can hold the single connection long
    # enough to starve it. The spare connection lets Oban boot.
    pool_size: 2,
    pool_timeout: 10_000,
    queue_target: 10_000,
    queue_interval: 1_000,
    timeout: 15_000,
    # Top-level options, not a `pragmas:` list — ecto_sqlite3 has no such key
    # and silently ignores it.
    foreign_keys: :on,
    journal_mode: :wal,
    synchronous: :normal,
    temp_store: :memory,
    busy_timeout: 10_000
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :gamend_web, GamendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1",
  server: false

# In test we don't send emails
config :gamend_core, Gamend.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Run Gamend.Async side effects inline so assertions observe them without
# racing, and so a task can't outlive the test's DB sandbox owner.
config :gamend_core, async_inline: true

# The periodic tournament tick has no sandbox connection in tests; leave the
# ticker supervised but idle. Tests drive Gamend.Tournaments.tick/0 directly.
config :gamend_core, Gamend.Tournaments.Ticker, enabled: false

# The live retention cycle would sweep outside any sandbox every minute; the
# full sweep's first run is five minutes out, past any test.
config :gamend_core, Gamend.Retention, live_interval_seconds: 0

# Same for the matchmaking sweep: no sandbox connection, and on SQLite it
# collides with the test's open write transaction ("database is locked").
# Tests drive Gamend.Matchmaking.Worker.sweep/0 directly.
config :gamend_core, Gamend.Matchmaking.Worker, enabled: false

# Same again for the chat-moderation boot load and mute sweep. Tests drive
# Gamend.Chat.Moderation.Cache.load_persisted/0 directly.
config :gamend_core, Gamend.Chat.Moderation.Sync, enabled: false

# Disable app-level caching in tests to avoid stale reads across assertions.
# Still provide the multilevel configuration so the cache can start.
config :gamend_core, Gamend.Cache,
  bypass_mode: true,
  inclusion_policy: :inclusive,
  levels: [
    {Gamend.Cache.L1, []}
  ]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure Guardian for testing
config :gamend_web, GamendWeb.Auth.Guardian,
  issuer: "gamend",
  secret_key: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1"

# Disable rate limiting in tests
config :gamend_web, GamendWeb.Plugs.RateLimiter, enabled: false

# Background presence sweeping fights with sandbox ownership in tests and can
# keep logging after the test task itself is done.
config :gamend_core, Gamend.Accounts.StalePresenceSweeper, enabled: false

# Write is_online through synchronously instead of coalescing it, so a test can
# assert on the flag immediately after set_user_online/1 and so a buffered write
# can never outlive the sandbox owner.
config :gamend_core, Gamend.Accounts.PresenceWriter, flush_ms: 0

# Jobs run inline on demand in tests (no queues/plugins/cron); assert with
# Oban.Testing helpers and drain explicitly. Keeps the Cron tick from firing
# against the Sandbox.
config :gamend_core, Oban, testing: :manual

# The declared setting, not just the endpoint's copy: Gamend.Settings
# validates `auth.secret_key_base` at boot, and dev should not warn about a
# secret it demonstrably has.
config :gamend_core, Gamend.Accounts,
  secret_key_base: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1"

# Uploads land in the system tmp dir, not priv/, so a test run leaves no
# objects behind in the checkout.
config :gamend_core, Gamend.Storage.Local,
  dir: Path.join(System.tmp_dir!(), "gamend_test_storage")

# Payments run against fake provider adapters here, and their fixtures report
# `environment: "test"`. `Gamend.Payments` refuses to fulfil a transaction whose
# environment is not the configured one — that is what stops a TestFlight or
# sandbox receipt buying real goods on a production server — so the test suite
# has to declare that it is not a production payment environment.
config :gamend_core, Gamend.Payments.Settings, environment: :sandbox
