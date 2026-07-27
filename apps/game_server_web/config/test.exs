import Config

config :bcrypt_elixir, :log_rounds, 1

if System.get_env("GAMEND_DB_URL") ||
     (System.get_env("GAMEND_DB_POSTGRES_HOST") && System.get_env("GAMEND_DB_POSTGRES_USER")) do
  database_url =
    System.get_env("GAMEND_DB_URL") ||
      "ecto://#{System.get_env("GAMEND_DB_POSTGRES_USER")}:#{System.get_env("GAMEND_DB_POSTGRES_PASSWORD")}@#{System.get_env("GAMEND_DB_POSTGRES_HOST")}:#{System.get_env("GAMEND_DB_POSTGRES_PORT", "5432")}/#{System.get_env("GAMEND_DB_POSTGRES_DB", "game_server_web_test")}"

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
  database_path =
    Path.expand(
      "../priv/db/game_server_web_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      __DIR__
    )

  File.mkdir_p!(Path.dirname(database_path))

  config :game_server_core, GameServer.Repo,
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
    pragmas: [
      foreign_keys: :on,
      journal_mode: :wal,
      synchronous: :normal,
      temp_store: :memory,
      busy_timeout: 10_000
    ]
end

config :game_server_web, GameServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1",
  server: false

config :game_server_core, GameServer.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false

config :logger, level: :warning

config :game_server_core, GameServer.Cache,
  bypass_mode: true,
  inclusion_policy: :inclusive,
  levels: [
    {GameServer.Cache.L1, []}
  ]

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :game_server_web, GameServerWeb.Auth.Guardian,
  issuer: "game_server",
  secret_key: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1",
  ttl: {15, :minutes}

config :game_server_web, GameServerWeb.Plugs.RateLimiter, enabled: false

# Background presence sweeping fights with sandbox ownership in tests and can
# keep logging after the test task itself is done.
config :game_server_core, GameServer.Accounts.StalePresenceSweeper, enabled: false

# The other periodic workers, for the same reason: neither owns a sandbox
# connection, and on SQLite they collide with the test's open write transaction
# ("database is locked"). Tests drive tick/0 and sweep/0 directly.
config :game_server_core, GameServer.Tournaments.Ticker, enabled: false
config :game_server_core, GameServer.Matchmaking.Worker, enabled: false

# NOTE: deliberately NOT setting `async_inline: true` here, unlike the root
# config/test.exs. Payments call GameServer.Async.run/1 from inside a
# Repo.transaction, and the hook fanout blocks on a Task that needs its own
# connection — inline, that Task waits on the connection its own caller is
# holding for the transaction, times out after 15s and rolls back. It fails
# 7 payments/entitlement tests. The stray "client exited" disconnects that
# inline mode would silence need a fix in Async/Hooks, not this knob.

# Jobs run inline on demand in tests (no queues/plugins/cron). Kept in sync with
# the root config/test.exs.
config :game_server_core, Oban, testing: :manual

# The declared setting, not just the endpoint's copy: GameServer.Settings
# validates `auth.secret_key_base` at boot, and dev should not warn about a
# secret it demonstrably has.
config :game_server_core, GameServer.Accounts,
  secret_key_base: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1"
