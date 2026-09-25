import Config

# The core settings every suite runs with. `gamend_web`'s config/test.exs
# imports this file and adds the web app's own, so the two suites cannot drift
# apart on how the core behaves under test.

config :bcrypt_elixir, :log_rounds, 1

# Named after the project running the suite, so gamend_core and gamend_web —
# which imports this file — each test against their own database.
test_app = Mix.Project.config()[:app]
test_database = "#{test_app}_test"

if System.get_env("GAMEND_DB_URL") ||
     (System.get_env("GAMEND_DB_POSTGRES_HOST") && System.get_env("GAMEND_DB_POSTGRES_USER")) do
  database_url =
    System.get_env("GAMEND_DB_URL") ||
      "ecto://#{System.get_env("GAMEND_DB_POSTGRES_USER")}:#{System.get_env("GAMEND_DB_POSTGRES_PASSWORD")}@#{System.get_env("GAMEND_DB_POSTGRES_HOST")}:#{System.get_env("GAMEND_DB_POSTGRES_PORT", "5432")}/#{System.get_env("GAMEND_DB_POSTGRES_DB", test_database)}"

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
  database_path =
    Path.join([
      Path.dirname(Mix.Project.project_file()),
      "priv/db",
      "#{test_database}#{System.get_env("MIX_TEST_PARTITION")}.db"
    ])

  File.mkdir_p!(Path.dirname(database_path))

  config :gamend_core, Gamend.Repo,
    database: database_path,
    adapter: Ecto.Adapters.SQLite3,
    # Match production: see the note in config/host_runtime.exs.
    default_transaction_mode: :immediate,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 1,
    pool_timeout: 10_000,
    queue_target: 10_000,
    queue_interval: 1_000,
    timeout: 15_000,
    # Top-level options, not a `pragmas:` list — ecto_sqlite3 has no such key
    # and silently ignores it, so this suite ran without WAL and with exqlite's
    # 2000ms busy_timeout default. That is the "Database busy" flakiness.
    foreign_keys: :on,
    journal_mode: :wal,
    synchronous: :normal,
    temp_store: :memory,
    busy_timeout: 10_000
end

config :gamend_core, Gamend.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false

config :logger, level: :warning

config :gamend_core, Gamend.Cache,
  bypass_mode: true,
  inclusion_policy: :inclusive,
  levels: [
    {Gamend.Cache.L1, []}
  ]

# Background presence sweeping fights with sandbox ownership in tests and can
# keep logging after the test task itself is done.
config :gamend_core, Gamend.Accounts.StalePresenceSweeper, enabled: false

# Write is_online through synchronously instead of coalescing it, so a test can
# assert on the flag immediately after set_user_online/1 and so a buffered write
# can never outlive the sandbox owner.
config :gamend_core, Gamend.Accounts.PresenceWriter, flush_ms: 0

# The other periodic workers, for the same reason: neither owns a sandbox
# connection, and on SQLite they collide with the test's open write transaction
# ("database is locked"). Tests drive tick/0 and sweep/0 directly.
config :gamend_core, Gamend.Tournaments.Ticker, enabled: false

# The live retention cycle would sweep outside any sandbox every minute; the
# full sweep's first run is five minutes out, past any test.
config :gamend_core, Gamend.Retention, live_interval_seconds: 0
config :gamend_core, Gamend.Matchmaking.Worker, enabled: false

# NOTE: deliberately NOT setting `async_inline: true` here, unlike the root
# config/test.exs. Payments call Gamend.Async.run/1 from inside a
# Repo.transaction, and the hook fanout blocks on a Task that needs its own
# connection — inline, that Task waits on the connection its own caller is
# holding for the transaction, times out after 15s and rolls back. It fails
# 7 payments/entitlement tests. The stray "client exited" disconnects that
# inline mode would silence need a fix in Async/Hooks, not this knob.

# Jobs run inline on demand in tests (no queues/plugins/cron). Kept in sync with
# the root config/test.exs.
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

# The server's deployment environment is the host's `:gamend_web` key, and a
# few core readers — the Google RTDN webhook's fail-closed check among them —
# default it to `:prod` when unset. The web app sets it from `config_env()`;
# the core suite runs without the web app, so it says `:test` itself.
config :gamend_web, environment: :test
