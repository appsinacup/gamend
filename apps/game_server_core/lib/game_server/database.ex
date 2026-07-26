defmodule GameServer.Database do
  @moduledoc """
  Connection and tuning settings for `GameServer.Repo`.

  The adapter is chosen at **compile** time (see `config/host_config.exs`), so
  `adapter` here is documentation and admin display rather than something a
  restart can change — the app refuses to start on a stale build and says so.

  `GAMEND_DB_URL` and the `POSTGRES_*` family are inherited names: platforms
  provision them, and renaming them would break every managed-database
  attachment.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :db,
    label: "Database"

  setting(:adapter, :atom,
    default: :sqlite,
    doc: "sqlite or postgres. Compile-time; set as a build arg, not at boot."
  )

  setting(:url, :string,
    secret: true,
    doc: "Full ecto:// URL. Takes precedence over the individual postgres_* values."
  )

  setting(:postgres_host, :string)
  setting(:postgres_port, :integer, default: 5432)
  setting(:postgres_user, :string)
  setting(:postgres_password, :string, secret: true)
  setting(:postgres_db, :string)

  setting(:ipv6, :boolean,
    default: false,
    doc: "Connect over IPv6, needed on platforms with IPv6-only private networking."
  )

  # SQLite has a single-writer model: a large pool usually adds lock contention
  # rather than throughput, which is why the default differs by adapter.
  setting(:pool_size, :integer,
    doc: "Connections in the pool. Defaults to 10 on Postgres, 5 on SQLite."
  )

  setting(:pool_timeout_ms, :integer,
    default: 10_000,
    doc: "How long a request waits to check out a connection, in milliseconds."
  )

  setting(:queue_target, :integer, default: 10_000)
  setting(:queue_interval_ms, :integer, default: 1_000)
  setting(:query_timeout_ms, :integer, default: 15_000)

  setting(:sqlite_path, :string,
    doc: "Where the SQLite file lives. Point at a mounted volume in production."
  )

  setting(:sqlite_synchronous, :atom,
    default: :normal,
    doc: "off | normal | full | extra. Lower means fewer fsyncs and less durability."
  )

  setting(:sqlite_cache_size_kb, :integer, default: 200_000)

  setting(:sqlite_busy_timeout_ms, :integer,
    default: 15_000,
    doc: "Wait this long for a lock instead of failing with \"database is locked\"."
  )

  setting(:sqlite_wal_autocheckpoint, :integer, default: 2_000)
end
