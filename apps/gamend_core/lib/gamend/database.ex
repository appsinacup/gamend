defmodule Gamend.Database do
  @moduledoc """
  Connection and tuning settings for `Gamend.Repo`.

  The adapter is chosen at **compile** time (see `config/host_config.exs`), so
  `adapter` here is documentation and admin display rather than something a
  restart can change — the app refuses to start on a stale build and says so.

  `GAMEND_DB_URL` and the `POSTGRES_*` family are inherited names: platforms
  provision them, and renaming them would break every managed-database
  attachment.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :db,
    label: "Database"

  setting(:adapter, :atom,
    values: [:sqlite, :postgres],
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

  # PostgreSQL's own default is `on`: every commit waits for the WAL to reach
  # disk. `off` returns as soon as the commit is in the WAL buffer, which on
  # the load-test harness is +71% on KV writes (3,096/s with fsync, 7,448/s
  # without) for a bounded exposure — an OS or hardware crash can lose the
  # last `wal_writer_delay`-ish window of commits, about 600ms by default.
  #
  # The data stays *consistent* either way; this is not `fsync = off`. Nothing
  # is corrupted, a recent commit is simply not there. That is the right trade
  # for progress, inventory and leaderboard rows and the wrong one for money,
  # so `Gamend.Repo.durable_transaction/2` forces `on` for the length of a
  # payment regardless of what this is set to.
  #
  # Defaulted to `off` rather than to PostgreSQL's `on`, because gamend knows
  # something a general-purpose database does not: which of its writes are
  # money. `Gamend.Repo.durable_transaction/2` puts `on` back for the length
  # of a payment, so the write that must not vanish never rides on this.
  # Everything else is progress a player can re-earn in the seconds before a
  # power cut. Set it to `on` to opt back into PostgreSQL's default.
  #
  # This also brings the two adapters level: SQLite already makes exactly this
  # trade on your behalf with `synchronous = NORMAL`.
  setting(:postgres_synchronous_commit, :atom,
    values: [:on, :off, :local, :remote_write, :remote_apply],
    default: :off,
    doc:
      "on | off | local | remote_write | remote_apply. Defaults to `off`: up to ~600ms " <>
        "of commits are exposed to an OS crash in exchange for markedly faster writes. " <>
        "Payments always commit synchronously regardless. Postgres only."
  )

  setting(:ipv6, :boolean,
    default: false,
    doc: "Connect over IPv6, needed on platforms with IPv6-only private networking."
  )

  # SQLite has a single-writer model, so more connections means more of them
  # racing for the same write lock — and SQLite's busy-retry backoff is not
  # FIFO, so a waiting connection can be passed over repeatedly. One connection
  # turns that race into a queue. See the measurements in
  # `GamendWeb.HostRuntime` where the adapter default is applied.
  setting(:pool_size, :integer,
    doc: "Connections in the pool. Defaults to 10 on Postgres, 1 on SQLite."
  )

  setting(:pool_timeout_ms, :integer,
    default: 10_000,
    doc: "How long a request waits to check out a connection, in milliseconds."
  )

  setting(:queue_target, :integer, default: 10_000)
  setting(:queue_interval_ms, :integer, default: 1_000)
  setting(:query_timeout_ms, :integer, default: 15_000)

  setting(:slow_query_ms, :integer,
    default: 1_000,
    doc:
      "Log a query that runs, or waits for a connection, longer than N ms, with " <>
        "where in the code it came from (`Gamend.Repo.SlowLog`). 0 turns it off."
  )

  setting(:slow_transaction_ms, :integer,
    default: 2_000,
    doc:
      "Log a transaction that holds its connection longer than N ms. On SQLite that " <>
        "is the write lock others wait on, so this names what a \"database is locked\" " <>
        "waited for. 0 turns it off."
  )

  setting(:sqlite_path, :string,
    doc: "Where the SQLite file lives. Point at a mounted volume in production."
  )

  setting(:sqlite_synchronous, :atom,
    values: [:off, :normal, :full, :extra],
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
