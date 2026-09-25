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

config :gamend_web, GamendWeb.Plugs.RateLimiter, enabled: false

# The IP-ban boot load holds a database connection the tests need. Tests drive
# GamendWeb.Plugs.IpBan.load_persisted/0 directly.
config :gamend_web, GamendWeb.IpBanSync, enabled: false
