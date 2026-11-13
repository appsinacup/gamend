import Config

config :gamend_core, ecto_repos: [Gamend.Repo]

default_adapter =
  if System.get_env("GAMEND_DB_ADAPTER") == "postgres",
    do: Ecto.Adapters.Postgres,
    else: Ecto.Adapters.SQLite3

config :gamend_core, Gamend.Repo,
  adapter: default_adapter,
  # All tables use UUID (v7) primary/foreign keys — see Gamend.UUIDv7.
  migration_primary_key: [name: :id, type: :binary_id, null: false],
  migration_foreign_key: [type: :binary_id]

# Background jobs (Gamend.Jobs / Gamend.Schedule). The `:engine` is
# injected at runtime from the Repo's actual adapter by
# Gamend.Jobs.oban_config/0. Kept in sync with config/host_config.exs.
config :gamend_core, Oban,
  repo: Gamend.Repo,
  queues: [default: 10, hooks: 20, mailers: 5, storage: 5, webhooks: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [{"* * * * *", Gamend.Schedule.TickWorker}]},
    # A job cut off by a restart stays `executing` for ever without it. The
    # rescue is by time alone, so it waits well past core's longest job (a
    # plugin hook's `call_timeout_ms`, a minute; a mail's 60 s timeout): one
    # rescued while still running would run twice.
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ]

# Object storage — defaults to local disk (see config/host_config.exs).
config :gamend_core, Gamend.Storage, adapter: :local
config :ex_aws, json_codec: Jason

config :gamend_core, Gamend.Mailer, adapter: Swoosh.Adapters.Local

config :gamend_core, Gamend.Cache,
  inclusion_policy: :inclusive,
  levels: [
    {Gamend.Cache.L1, []}
  ]

# MDEx renders every markdown surface (guides, blog, changelog). Its NIF only
# builds in the syntax highlighter when told to at compile time, and each app
# that compiles the NIF needs the flag - otherwise fenced code renders as one
# undifferentiated colour, or raises once highlighting is requested.
config :mdex_native, syntax_highlighter: :lumis

if config_env() == :test, do: import_config("test.exs")
