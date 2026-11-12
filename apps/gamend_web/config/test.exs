import Config

# The core's own test settings (repo, cache, workers, payments) come in through
# gamend_core's config.exs, imported by this app's. The database is named after
# the project running the suite, so the two suites never share one.

config :gamend_web, GamendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1",
  server: false

# Check every documented API response against its OpenAPI schema
# (GamendWeb.ResponseContract; docs/specs/named-api-schemas.md).
config :gamend_web, :response_contract, true

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :gamend_web, GamendWeb.Auth.Guardian,
  issuer: "gamend",
  secret_key: "dJoNJZBOt08JlBREyPV5xvuOdwgHPORxK9WHp/k3Cs+g0R9ctyheJ8/CMeg/AdI1",
  ttl: {15, :minutes}

# A test that turns rate limiting on counts in windows that never turn over:
# Hammer's ETS backend counts in fixed windows aligned to the epoch
# (`div(now, scale)`), so a 60s window starts again at every minute, and a test
# whose hits straddle one sees its count reset. A window longer than the time
# since the epoch stays the first one. Same as the root `config/test.exs`.
never_turns_over = :timer.hours(24 * 365 * 1000)

config :gamend_web, GamendWeb.Plugs.RateLimiter,
  enabled: false,
  general_window_ms: never_turns_over,
  auth_window_ms: never_turns_over,
  client_logs_window_ms: never_turns_over,
  ws_window_ms: never_turns_over,
  dc_window_ms: never_turns_over,
  ice_window_ms: never_turns_over,
  signaling_ws_window_ms: never_turns_over,
  signaling_ice_window_ms: never_turns_over

# A cold test request (first render, first query) routinely passes the 200ms
# slow-request threshold, and each one would print a warning into the run.
# Tests that assert on the log lower it themselves.
config :gamend_web, :slow_request_threshold_ms, 60_000.0

# The ban boot load holds a database connection the tests need. Tests drive
# Gamend.Bans.Cache.load_persisted/0 directly.
config :gamend_core, Gamend.Bans.Sync, enabled: false
# The ban kick reads session tokens outside the sandbox; tests call kick/1.
config :gamend_web, GamendWeb.AccountBanKicks, enabled: false
