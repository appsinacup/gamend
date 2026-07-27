import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# .env is already loaded by host_config.exs during config evaluation; this is
# kept as a safety net for hosts whose compile-time config doesn't load it.
# (Code.require_file is a no-op when the file was already required.)
if config_env() == :dev do
  Code.require_file("dotenv.exs", __DIR__)
  GameServer.Dotenv.load(Path.expand("../.env", __DIR__))
end

# Resolved once, for the derivations further down: they turn settings into the
# shapes Phoenix, Ecto, Bandit, Swoosh and Pigeon expect, and cannot read back
# what `config/2` has staged.
settings = GameServer.Settings.resolve()
setting = fn module, key -> Map.get(settings, {module, key}) end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the GAMEND_HTTP_SERVER=true when you start it:
#
#     GAMEND_HTTP_SERVER=true bin/game_server_web start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if setting.(GameServerWeb.Http, :server) do
  config :game_server_web, GameServerWeb.Endpoint, server: true
end

# Logger's own level is not ours to declare — mirror the declared setting onto
# the :logger application, which is what actually filters.
# The setting is already cast to a level atom.
if log_level = setting.(GameServerWeb.Observability, :log_level) do
  config :logger, level: log_level
end

host = setting.(GameServerWeb.Http, :host) || "localhost"

scheme =
  setting.(GameServerWeb.Http, :scheme) ||
    if host in ["localhost", "127.0.0.1"], do: "http", else: "https"

# ── OAuth providers ─────────────────────────────────────────────────────────
# Ueberauth resolves credentials from its own application env, so the declared
# settings are written into it here — in every environment, for every provider.
# Nothing reads provider credentials from the environment directly.
config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: setting.(GameServer.OAuth.Providers, :discord_client_id),
  client_secret: setting.(GameServer.OAuth.Providers, :discord_client_secret)

config :ueberauth, Ueberauth.Strategy.Apple.OAuth,
  client_id: setting.(GameServer.OAuth.Providers, :apple_client_id),
  client_secret: {GameServer.Apple, :client_secret},
  redirect_uri: "#{scheme}://#{host}/auth/apple/callback"

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: setting.(GameServer.OAuth.Providers, :google_client_id),
  client_secret: setting.(GameServer.OAuth.Providers, :google_client_secret)

config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
  client_id: setting.(GameServer.OAuth.Providers, :facebook_client_id),
  client_secret: setting.(GameServer.OAuth.Providers, :facebook_client_secret)

config :ueberauth, Ueberauth.Strategy.Steam,
  api_key: setting.(GameServer.OAuth.Providers, :steam_api_key)

# ── Mailer ──────────────────────────────────────────────────────────────────
# Dev and prod resolve the mailer the same way: SMTP when a password is
# declared, the local mailbox otherwise. Dev used to carry its own copy of this
# and drifted onto env names that no longer exist. Test keeps the capture
# adapter it pins in config/test.exs — runtime config would otherwise win.
if config_env() != :test and setting.(GameServer.Mail, :smtp_password) do
  # gen_smtp expects a charlist for server_name_indication; a binary raises
  # "incompatible options". Computed outside the keyword list so no remote call
  # ends up in a guard.
  sni_env = setting.(GameServer.Mail, :smtp_sni) || setting.(GameServer.Mail, :smtp_relay)

  sni =
    if is_binary(sni_env) do
      trimmed = String.trim(sni_env)
      if trimmed != "", do: String.to_charlist(trimmed), else: nil
    end

  config :game_server_core, GameServer.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: setting.(GameServer.Mail, :smtp_relay),
    username: setting.(GameServer.Mail, :smtp_username),
    password: setting.(GameServer.Mail, :smtp_password),
    port: setting.(GameServer.Mail, :smtp_port),
    tls: setting.(GameServer.Mail, :smtp_tls),
    ssl: setting.(GameServer.Mail, :smtp_ssl),
    retries: 2,
    auth: :always,
    no_mx_lookups: false,
    sockopts: [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ],
      server_name_indication: sni
    ]

  config :swoosh, :api_client, Swoosh.ApiClient.Req
else
  if config_env() != :test do
    config :game_server_core, GameServer.Mailer, adapter: Swoosh.Adapters.Local

    # Swoosh's in-memory mailbox backs the preview page.
    config :swoosh, local: true
    config :swoosh, :api_client, false
  end
end

# ── Push notifications ──────────────────────────────────────────────────────
# (docs/specs/push.md) With nothing set, neither dispatcher is configured, so
# GameServer.Push.Supervisor starts no children and every delivery routes to
# the Log provider. Credentials are parse-validated here so a bad value
# degrades to that Log fallback with one loud error instead of handing the
# dispatcher a config it would crash-loop on.

# Secret env vars accept inline contents or a path to a file holding them.
read_push_secret = fn
  nil -> nil
  "" -> nil
  value -> if File.regular?(value), do: File.read!(value), else: value
end

# The push queue lives in Oban's config, so the declared concurrency has to be
# copied across rather than read from the setting at runtime.
case setting.(GameServer.Push, :queue_concurrency) do
  concurrency when is_integer(concurrency) and concurrency > 0 ->
    config :game_server_core, Oban, queues: [push: concurrency]

  _ ->
    :ok
end

fcm_credentials = read_push_secret.(setting.(GameServer.Push, :fcm_credentials))

if fcm_credentials do
  case Jason.decode(fcm_credentials) do
    {:ok, %{} = credentials} ->
      project_id = setting.(GameServer.Push, :fcm_project_id) || credentials["project_id"]

      if project_id in [nil, ""] do
        IO.puts(
          :stderr,
          "[push] GAMEND_PUSH_FCM_CREDENTIALS has no project_id and GAMEND_PUSH_FCM_PROJECT_ID is unset — " <>
            "FCM disabled, deliveries fall back to the Log provider"
        )
      else
        config :game_server_core, GameServer.Push.Goth,
          source: {:service_account, credentials, []}

        config :game_server_core, GameServer.Push.FCMDispatcher,
          adapter: Pigeon.FCM,
          auth: GameServer.Push.Goth,
          project_id: project_id
      end

    {:error, _} ->
      IO.puts(
        :stderr,
        "[push] GAMEND_PUSH_FCM_CREDENTIALS is neither valid service-account JSON nor a readable " <>
          "file — FCM disabled, deliveries fall back to the Log provider"
      )
  end
end

apns_key = read_push_secret.(setting.(GameServer.Push, :apns_private_key))
apns_key_id = setting.(GameServer.Push, :apns_key_id)
apns_team_id = setting.(GameServer.Push, :apns_team_id)
apns_topic = setting.(GameServer.Push, :apns_topic)
apns_vars = [apns_key, apns_key_id, apns_team_id, apns_topic]

cond do
  Enum.all?(apns_vars, &(&1 in [nil, ""])) ->
    :ok

  Enum.any?(apns_vars, &(&1 in [nil, ""])) ->
    IO.puts(
      :stderr,
      "[push] APNs needs all of APNS_PRIVATE_KEY, APNS_KEY_ID, APNS_TEAM_ID and APNS_TOPIC — " <>
        "APNs disabled, deliveries fall back to the Log provider"
    )

  not String.contains?(apns_key, "PRIVATE KEY") ->
    IO.puts(
      :stderr,
      "[push] APNS_PRIVATE_KEY does not look like .p8 key contents (or a path to them) — " <>
        "APNs disabled, deliveries fall back to the Log provider"
    )

  true ->
    config :game_server_core, GameServer.Push.APNSDispatcher,
      adapter: Pigeon.APNS,
      key: apns_key,
      key_identifier: apns_key_id,
      team_id: apns_team_id,
      mode: if(setting.(GameServer.Push, :apns_env) == "sandbox", do: :dev, else: :prod)

    config :game_server_core, GameServer.Push, apns_topic: apns_topic
end

# ── Declared settings ───────────────────────────────────────────────────────
# Every setting declared with GameServer.Settings.Provider, read from the
# environment once at boot. Blocks below this line are the ones not yet
# converted; each disappears as its section is declared.
for {app, module, opts} <- GameServer.Settings.from_env() do
  config app, module, opts
end

# Outside prod the cache topology comes from the compiled config; honor the
# GAMEND_CACHE_ENABLED toggle here so disabling it in dev/test isn't a silent no-op.
unless config_env() == :prod do
  config :game_server_core, GameServer.Cache,
    bypass_mode: not setting.(GameServer.Cache.Settings, :enabled)
end

if config_env() == :prod do
  cache_enabled = setting.(GameServer.Cache.Settings, :enabled)

  cache_mode = setting.(GameServer.Cache.Settings, :mode)
  cache_l2 = setting.(GameServer.Cache.Settings, :l2)

  redis_conn_opts =
    case setting.(GameServer.Cache.Settings, :redis_url) ||
           setting.(GameServer.Cluster, :redis_url) do
      nil ->
        []

      url ->
        uri = URI.parse(url)

        host = uri.host || "127.0.0.1"
        port = uri.port || 6379

        password =
          case uri.userinfo do
            nil -> nil
            userinfo -> userinfo |> String.split(":", parts: 2) |> List.last()
          end

        database =
          case uri.path do
            "/" <> db_str when db_str != "" ->
              case Integer.parse(db_str) do
                {db, _} -> db
                :error -> nil
              end

            _ ->
              nil
          end

        [host: host, port: port]
        |> then(fn opts ->
          if password, do: Keyword.put(opts, :password, password), else: opts
        end)
        |> then(fn opts ->
          if database != nil, do: Keyword.put(opts, :database, database), else: opts
        end)
    end

  l1_opts = [
    # Create new generation every 12 hours
    gc_interval: :timer.hours(12),
    # Max 1M entries
    max_size: 1_000_000,
    # Max 500MB of memory
    allocated_memory: 500_000_000,
    # Run size and memory checks every 10 seconds
    gc_memory_check_interval: :timer.seconds(10)
  ]

  levels =
    case cache_mode do
      :single ->
        [{GameServer.Cache.L1, l1_opts}]

      _ ->
        l2_level =
          case cache_l2 do
            :redis ->
              pool_size = setting.(GameServer.Cache.Settings, :redis_pool_size)

              if redis_conn_opts == [] do
                raise "GAMEND_CACHE_MODE=multi with GAMEND_CACHE_L2=redis requires GAMEND_CACHE_REDIS_URL or REDIS_URL"
              end

              {GameServer.Cache.L2.Redis, pool_size: pool_size, conn_opts: redis_conn_opts}

            _ ->
              {GameServer.Cache.L2.Partitioned,
               primary: [
                 # Partitioned uses a local primary storage on each node.
                 gc_interval: :timer.hours(12),
                 max_size: 1_000_000,
                 allocated_memory: 500_000_000,
                 gc_memory_check_interval: :timer.seconds(10)
               ]}
          end

        [{GameServer.Cache.L1, l1_opts}, l2_level]
    end

  config :game_server_core, GameServer.Cache,
    bypass_mode: not cache_enabled,
    inclusion_policy: :inclusive,
    levels: levels

  config :game_server_web, GameServerWeb.Endpoint,
    access_log: GameServer.Settings.get(GameServerWeb.Observability, :access_log_level)

  # Check if PostgreSQL environment variables are set
  has_postgres_config =
    setting.(GameServer.Database, :url) ||
      (setting.(GameServer.Database, :postgres_host) &&
         setting.(GameServer.Database, :postgres_user))

  # NOTE: SQLite has a single-writer concurrency model. A very large pool
  # usually increases contention/lock waits rather than throughput.
  # The declared setting has no default because the sensible one depends on the
  # adapter, which is only known here.
  default_pool_size = if has_postgres_config, do: 10, else: 5

  repo_pool_size = setting.(GameServer.Database, :pool_size) || default_pool_size

  # Backpressure/overload tuning:
  # - pool_timeout: how long a request waits for a DB connection checkout (ms)
  # - queue_target/queue_interval: DBConnection queueing algorithm (ms)
  # - timeout: query timeout (ms)
  # NOTE: Increasing queue_target/interval makes requests wait longer (can increase memory under load).
  # Default to more forgiving backpressure in prod to avoid dropping requests too quickly
  # under bursty load. These can still be overridden via env vars.
  repo_pool_timeout = setting.(GameServer.Database, :pool_timeout_ms)
  repo_queue_target = setting.(GameServer.Database, :queue_target)
  repo_queue_interval = setting.(GameServer.Database, :queue_interval_ms)
  repo_query_timeout = setting.(GameServer.Database, :query_timeout_ms)

  if has_postgres_config do
    # Use PostgreSQL when configured
    database_url =
      setting.(GameServer.Database, :url) ||
        "ecto://#{setting.(GameServer.Database, :postgres_user)}:#{setting.(GameServer.Database, :postgres_password)}@#{setting.(GameServer.Database, :postgres_host)}:#{setting.(GameServer.Database, :postgres_port)}/#{setting.(GameServer.Database, :postgres_db)}"

    maybe_ipv6 = if setting.(GameServer.Database, :ipv6) in ~w(true 1), do: [:inet6], else: []

    config :game_server_core, GameServer.Repo,
      url: database_url,
      adapter: Ecto.Adapters.Postgres,
      pool_size: repo_pool_size,
      pool_timeout: repo_pool_timeout,
      queue_target: repo_queue_target,
      queue_interval: repo_queue_interval,
      timeout: repo_query_timeout,
      socket_options: maybe_ipv6
  else
    # Fallback to persistent SQLite when no PostgreSQL config
    # Use GAMEND_DB_SQLITE_PATH if set (e.g. a mounted Fly volume), otherwise default to the host-local db directory.
    default_db_path = Path.expand("../db/game_server_prod.db", __DIR__)

    db_path =
      case setting.(GameServer.Database, :sqlite_path) do
        nil ->
          File.mkdir_p!(Path.dirname(default_db_path))
          default_db_path

        override ->
          override
      end

    # SQLite performance/durability tuning.
    # - WAL: better read concurrency and typically fewer full-db fsyncs
    # - synchronous=normal: less fsync pressure vs full (tradeoff: slightly less durability)
    # - temp_store=memory: reduces disk writes for temp tables
    # - cache_size: in KiB when negative (e.g. -200_000 => ~200MB page cache)
    # - busy_timeout: wait for locks instead of immediate "database is locked" failures
    sqlite_synchronous =
      case setting.(GameServer.Database, :sqlite_synchronous) do
        "off" -> :off
        "normal" -> :normal
        "full" -> :full
        "extra" -> :extra
        _ -> :normal
      end

    sqlite_cache_size_kb = setting.(GameServer.Database, :sqlite_cache_size_kb)
    sqlite_busy_timeout_ms = setting.(GameServer.Database, :sqlite_busy_timeout_ms)
    sqlite_wal_autocheckpoint = setting.(GameServer.Database, :sqlite_wal_autocheckpoint)

    # Ensure Ecto/DBConnection timeout does not fire before SQLite's busy timeout.
    sqlite_query_timeout = max(repo_query_timeout, sqlite_busy_timeout_ms + 5_000)

    config :game_server_core, GameServer.Repo,
      database: db_path,
      adapter: Ecto.Adapters.SQLite3,
      pool_size: repo_pool_size,
      pool_timeout: repo_pool_timeout,
      queue_target: repo_queue_target,
      queue_interval: repo_queue_interval,
      timeout: sqlite_query_timeout,
      # IMMEDIATE, not the DEFERRED default: a deferred transaction that reads
      # before it writes has to *upgrade* its lock, and SQLite answers a
      # contended upgrade with SQLITE_BUSY straight away — `busy_timeout` only
      # covers waiting for a lock, never upgrading one. Read-modify-write paths
      # (quest progress, wallets, KV) crashed under concurrent logins because of
      # it. Taking the write lock up front means those waits honour the timeout.
      default_transaction_mode: :immediate,
      pragmas: [
        foreign_keys: :on,
        journal_mode: :wal,
        synchronous: sqlite_synchronous,
        temp_store: :memory,
        cache_size: -sqlite_cache_size_kb,
        busy_timeout: sqlite_busy_timeout_ms,
        wal_autocheckpoint: sqlite_wal_autocheckpoint
      ]
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  # Declared as `auth.secret_key_base` and enforced by
  # GameServer.Settings.validate!/1 at boot, which reports every missing
  # required setting at once rather than only the first.
  secret_key_base = setting.(GameServer.Accounts, :secret_key_base)

  # Guardian JWT secret - can be the same as secret_key_base or separate
  guardian_secret_key =
    setting.(GameServer.Accounts, :guardian_secret_key) || secret_key_base

  config :game_server_web, GameServerWeb.Auth.Guardian,
    issuer: "game_server",
    secret_key: guardian_secret_key,
    ttl: {15, :minutes}

  port = setting.(GameServerWeb.Http, :port)

  config :game_server_web, :dns_cluster_query, setting.(GameServer.Cluster, :dns_query)

  # The origin allowlist arrives already split — it is a declared `:list`, so
  # nothing here has to parse a comma-separated string. An entry prefixed with
  # `regex:` compiles to a pattern; a bare host is normalised to the
  # protocol-agnostic `//host` form Phoenix and Corsica both accept.
  normalize_origin = fn
    <<"regex:", pattern::binary>> ->
      Regex.compile!(pattern)

    origin ->
      if String.starts_with?(origin, "//") or String.starts_with?(origin, "http") do
        origin
      else
        "//" <> origin
      end
  end

  allowed_origins =
    Enum.map(setting.(GameServerWeb.Http, :allowed_origins) || [], normalize_origin)

  # nil lets Phoenix apply its own check_origin default; "*" is Corsica's
  # allow-any. Both mean "the operator did not restrict this".
  check_origin = if allowed_origins == [], do: nil, else: allowed_origins
  cors_allowed_origins = if allowed_origins == [], do: "*", else: allowed_origins

  # Expose these choices via application config so endpoint/plug can pick them up
  config :game_server_web, :cors_allowed_origins, cors_allowed_origins

  # Rate limiting is declared on GameServerWeb.Plugs.RateLimiter and
  # GameServerWeb.RateLimit; from_env/0 above resolves it. The redis URL still
  # falls back to the shared cache URL when only that is set.
  if setting.(GameServerWeb.RateLimit, :redis_url) in [nil, ""] do
    shared_redis =
      setting.(GameServer.Cache.Settings, :redis_url) || setting.(GameServer.Cluster, :redis_url)

    if shared_redis not in [nil, ""] do
      config :game_server_web, GameServerWeb.RateLimit, redis_url: shared_redis
    end
  end

  endpoint_config =
    [
      url: [host: host, port: if(scheme == "https", do: 443, else: port), scheme: scheme],
      http: [
        # Enable IPv6 and bind on all interfaces.
        # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
        # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
        # for details about using IPv6 vs IPv4 and loopback vs public addresses.
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: port
      ],
      secret_key_base: secret_key_base
    ]
    |> then(fn cfg ->
      if check_origin == nil, do: cfg, else: Keyword.put(cfg, :check_origin, check_origin)
    end)

  # ── HTTPS / TLS ─────────────────────────────────────────────────────────────
  # Enable native HTTPS directly in Phoenix/Bandit by setting GAMEND_TLS_CERTFILE and
  # GAMEND_TLS_KEYFILE to the paths of your certificate and private key PEM files.
  # Erlang's :ssl automatically reloads certificate files from disk, so
  # renewed certificates (e.g. from certbot) are picked up without restart.
  #
  # Environment variables:
  #   GAMEND_TLS_CERTFILE  — path to fullchain.pem (certificate + CA chain)
  #   GAMEND_TLS_KEYFILE   — path to privkey.pem
  #   GAMEND_TLS_PORT    — HTTPS listen port (default: 443)
  #   GAMEND_TLS_FORCE     — set to "true" to redirect HTTP → HTTPS and enable HSTS
  #   GAMEND_TLS_ACME_WEBROOT  — webroot directory for Let's Encrypt HTTP-01 challenge files
  #                   (default: /var/www/acme when SSL is enabled; same path you
  #                   pass to certbot --webroot-path)
  ssl_certfile = setting.(GameServerWeb.Tls, :certfile)
  ssl_keyfile = setting.(GameServerWeb.Tls, :keyfile)

  # Validate that certificate files actually exist before enabling HTTPS.
  # This prevents a crash on startup when GAMEND_TLS_CERTFILE/GAMEND_TLS_KEYFILE are set
  # but the files haven't been created yet (e.g. before running certbot).
  ssl_files_ready? =
    if ssl_certfile && ssl_keyfile do
      cert_exists? = File.exists?(ssl_certfile)
      key_exists? = File.exists?(ssl_keyfile)

      unless cert_exists? do
        require Logger

        Logger.warning(
          "GAMEND_TLS_CERTFILE is set to #{ssl_certfile} but the file does not exist. " <>
            "HTTPS will NOT be enabled. Run certbot to generate the certificate first, " <>
            "then restart the server."
        )
      end

      unless key_exists? do
        require Logger

        Logger.warning(
          "GAMEND_TLS_KEYFILE is set to #{ssl_keyfile} but the file does not exist. " <>
            "HTTPS will NOT be enabled. Run certbot to generate the certificate first, " <>
            "then restart the server."
        )
      end

      cert_exists? and key_exists?
    else
      false
    end

  endpoint_config =
    if ssl_files_ready? do
      https_port = setting.(GameServerWeb.Tls, :port)

      https_opts = [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: https_port,
        cipher_suite: :strong,
        certfile: ssl_certfile,
        keyfile: ssl_keyfile
        # Suppress noisy TLS handshake notices from bots/scanners
        # probing with old TLS versions or unsupported cipher suites.
      ]

      Keyword.put(endpoint_config, :https, https_opts)
    else
      endpoint_config
    end

  # ACME webroot for Let's Encrypt HTTP-01 validation.
  # Certbot (or any ACME client) writes challenge tokens to
  # <webroot>/.well-known/acme-challenge/<token>; the AcmeChallenge plug
  # serves them over HTTP so the CA can verify domain ownership.
  # This is the same path you pass to `certbot --webroot-path`.
  # Enabled whenever GAMEND_TLS_CERTFILE is set (even if the file doesn't exist yet)
  # so certbot can complete its first challenge.
  acme_webroot =
    setting.(GameServerWeb.Tls, :acme_webroot) ||
      if(ssl_certfile, do: "/var/www/acme")

  if acme_webroot do
    # Ensure the ACME webroot directory exists. If it doesn't, try to create
    # it so certbot can write challenge tokens before its first run. If creation
    # fails (e.g. permission denied), log a warning and skip the config so the
    # server doesn't emit confusing errors when serving challenge requests.
    acme_dir_ready? =
      if File.dir?(acme_webroot) do
        true
      else
        case File.mkdir_p(acme_webroot) do
          :ok ->
            true

          {:error, reason} ->
            require Logger

            Logger.warning(
              "ACME webroot directory #{acme_webroot} does not exist and could not be created " <>
                "(#{reason}). ACME HTTP-01 challenges will not be served. " <>
                "Create the directory manually: sudo mkdir -p #{acme_webroot}"
            )

            false
        end
      end

    if acme_dir_ready? do
      config :game_server_web, :acme_webroot, acme_webroot
    end
  end

  # Force SSL — redirect all HTTP to HTTPS and set HSTS header.
  # Only enabled when cert files actually exist (ssl_files_ready?), otherwise
  # we'd redirect to HTTPS that isn't listening and break the server.
  # The ACME challenge path and health-check endpoints are excluded so
  # certbot can complete HTTP-01 validation and load balancers can probe.
  force_ssl = setting.(GameServerWeb.Tls, :force)

  endpoint_config =
    if force_ssl do
      Keyword.put(endpoint_config, :force_ssl,
        rewrite_on: [:x_forwarded_proto, :x_forwarded_port],
        hsts: true,
        expires: 31_536_000,
        subdomains: true,
        preload: true,
        exclude: fn conn ->
          conn.host in ["localhost", "127.0.0.1"] or
            String.starts_with?(conn.request_path, "/.well-known/acme-challenge") or
            conn.request_path == "/api/v1/health"
        end
      )
    else
      endpoint_config
    end

  config :game_server_web, GameServerWeb.Endpoint, endpoint_config

  # ── GeoIP database ──
  # Prefer the host-owned default path under data/, but
  # still allow GAMEND_CONTENT_GEOIP_DB_PATH to override it for custom deployments.
  default_geoip_db = Path.expand("../data/GeoLite2-Country.mmdb", __DIR__)

  geoip_db =
    setting.(GameServer.ContentSettings, :geoip_db_path) ||
      if File.exists?(default_geoip_db), do: default_geoip_db, else: nil

  if geoip_db do
    config :geolix,
      databases: [
        %{
          id: :country,
          adapter: Geolix.Adapter.MMDB2,
          source: geoip_db
        }
      ]
  end
end
