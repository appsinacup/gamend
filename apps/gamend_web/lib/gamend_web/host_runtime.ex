defmodule GamendWeb.HostRuntime do
  @moduledoc """
  The boot-time configuration derivations every host shares: declared settings
  turned into the shapes Phoenix, Ecto, Bandit, Swoosh and Pigeon expect.

  This used to live only in this repo's `config/host_runtime.exs`, which host
  repos forked and let drift — one fork went 361 lines out of sync, another
  slimmed itself down to just the `Settings.from_env/0` loop and lost the Repo
  and Endpoint configuration entirely. Shipping the derivations as code means
  a host's `config/host_runtime.exs` is one loop:

      for entry <-
            GamendWeb.HostRuntime.config(config_env(),
              host_root: Path.expand("..", __DIR__)
            ) do
        case entry do
          {app, opts} -> config app, opts
          {app, key, value} -> config app, key, value
        end
      end

  `Gamend.Settings.from_env/0` is folded in, so the loop above is the
  entire settings layer; hosts add genuinely host-specific config after it.

  `host_root` anchors the host-relative defaults (`db/`, `data/`). Entries are
  `{app, opts}` for `config/2` and `{app, key, value}` for `config/3`, in the
  order they must be applied.
  """

  require Logger

  @type entry :: {atom(), keyword()} | {atom(), term(), term()}

  @spec config(:dev | :test | :prod, keyword()) :: [entry()]
  def config(env, opts \\ []) when env in [:dev, :test, :prod] do
    host_root = Keyword.fetch!(opts, :host_root)

    # Resolved once, for every derivation below: they cannot read back what
    # `config/2` has staged, so env + compiled defaults is the source of truth.
    settings = Gamend.Settings.resolve()
    setting = fn module, key -> Map.get(settings, {module, key}) end

    host = setting.(GamendWeb.Http, :host) || "localhost"

    scheme =
      setting.(GamendWeb.Http, :scheme) ||
        if host in ["localhost", "127.0.0.1"], do: "http", else: "https"

    server_entries(setting) ++
      log_level_entries(setting) ++
      oauth_entries(setting, scheme, host) ++
      mailer_entries(env, setting) ++
      push_entries(setting) ++
      declared_settings_entries() ++
      cache_bypass_entries(env, setting) ++
      prod_entries(env, setting, host, scheme, host_root)
  end

  # ── Releases ──────────────────────────────────────────────────────────────
  # `mix release` starts nothing unless told to; GAMEND_HTTP_SERVER=true is the
  # equivalent of PHX_SERVER for hosts built on this stack.
  defp server_entries(setting) do
    if setting.(GamendWeb.Http, :server) do
      [{:gamend_web, GamendWeb.Endpoint, [server: true]}]
    else
      []
    end
  end

  # Logger's own level is not ours to declare — mirror the declared setting
  # onto the :logger application, which is what actually filters.
  defp log_level_entries(setting) do
    if log_level = setting.(GamendWeb.Observability, :log_level) do
      [{:logger, [level: log_level]}]
    else
      []
    end
  end

  # ── OAuth providers ───────────────────────────────────────────────────────
  # Only the providers Ueberauth actually serves get their credentials mirrored
  # into its application env. Discord, Google, Facebook and GitHub are exchanged by
  # Gamend.OAuth.Exchanger, which reads Gamend.Settings at call time and never
  # consults this env; mirroring them here was dead config.
  defp oauth_entries(setting, scheme, host) do
    [
      {:ueberauth, Ueberauth.Strategy.Apple.OAuth,
       [
         client_id: setting.(Gamend.OAuth.Providers, :apple_client_id),
         client_secret: {Gamend.Apple, :client_secret},
         redirect_uri: "#{scheme}://#{host}/auth/apple/callback"
       ]},
      {:ueberauth, Ueberauth.Strategy.Steam,
       [api_key: setting.(Gamend.OAuth.Providers, :steam_api_key)]}
    ]
  end

  # ── Mailer ────────────────────────────────────────────────────────────────
  # Dev and prod resolve the mailer the same way: SMTP when a password is
  # declared, the local mailbox otherwise. Test keeps the capture adapter it
  # pins in config/test.exs — runtime config would otherwise win.
  defp mailer_entries(:test, _setting), do: []

  defp mailer_entries(_env, setting) do
    if setting.(Gamend.Mail, :smtp_password) do
      # gen_smtp expects a charlist for server_name_indication; a binary raises
      # "incompatible options".
      sni_env = setting.(Gamend.Mail, :smtp_sni) || setting.(Gamend.Mail, :smtp_relay)

      sni =
        if is_binary(sni_env) do
          trimmed = String.trim(sni_env)
          if trimmed != "", do: String.to_charlist(trimmed), else: nil
        end

      [
        {:gamend_core, Gamend.Mailer,
         [
           adapter: Swoosh.Adapters.SMTP,
           relay: setting.(Gamend.Mail, :smtp_relay),
           username: setting.(Gamend.Mail, :smtp_username),
           password: setting.(Gamend.Mail, :smtp_password),
           port: setting.(Gamend.Mail, :smtp_port),
           tls: setting.(Gamend.Mail, :smtp_tls),
           ssl: setting.(Gamend.Mail, :smtp_ssl),
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
         ]},
        {:swoosh, :api_client, Swoosh.ApiClient.Req}
      ]
    else
      [
        {:gamend_core, Gamend.Mailer, [adapter: Swoosh.Adapters.Local]},
        # Swoosh's in-memory mailbox backs the preview page.
        {:swoosh, [local: true]},
        {:swoosh, :api_client, false}
      ]
    end
  end

  # ── Push notifications ────────────────────────────────────────────────────
  # (see Gamend.Push) With nothing set, neither dispatcher is configured,
  # so Gamend.Push.Supervisor starts no children and every delivery routes
  # to the Log provider. Credentials are parse-validated here so a bad value
  # degrades to that Log fallback with one loud error instead of handing the
  # dispatcher a config it would crash-loop on.
  # The push queue's concurrency is applied with the other queues', by
  # Gamend.Jobs.oban_config/0.
  defp push_entries(setting) do
    fcm_entries(setting) ++ apns_entries(setting)
  end

  # Secret env vars accept inline contents or a path to a file holding them.
  defp read_push_secret(nil), do: nil
  defp read_push_secret(""), do: nil
  defp read_push_secret(value), do: if(File.regular?(value), do: File.read!(value), else: value)

  defp fcm_entries(setting) do
    case read_push_secret(setting.(Gamend.Push, :fcm_credentials)) do
      nil ->
        []

      fcm_credentials ->
        case Jason.decode(fcm_credentials) do
          {:ok, %{} = credentials} ->
            project_id = setting.(Gamend.Push, :fcm_project_id) || credentials["project_id"]

            if project_id in [nil, ""] do
              IO.puts(
                :stderr,
                "[push] GAMEND_PUSH_FCM_CREDENTIALS has no project_id and GAMEND_PUSH_FCM_PROJECT_ID is unset — " <>
                  "FCM disabled, deliveries fall back to the Log provider"
              )

              []
            else
              [
                {:gamend_core, Gamend.Push.Goth, [source: {:service_account, credentials, []}]},
                {:gamend_core, Gamend.Push.FCMDispatcher,
                 [adapter: Pigeon.FCM, auth: Gamend.Push.Goth, project_id: project_id]}
              ]
            end

          {:error, _} ->
            IO.puts(
              :stderr,
              "[push] GAMEND_PUSH_FCM_CREDENTIALS is neither valid service-account JSON nor a readable " <>
                "file — FCM disabled, deliveries fall back to the Log provider"
            )

            []
        end
    end
  end

  defp apns_entries(setting) do
    apns_key = read_push_secret(setting.(Gamend.Push, :apns_private_key))
    apns_key_id = setting.(Gamend.Push, :apns_key_id)
    apns_team_id = setting.(Gamend.Push, :apns_team_id)
    apns_topic = setting.(Gamend.Push, :apns_topic)
    apns_vars = [apns_key, apns_key_id, apns_team_id, apns_topic]

    cond do
      Enum.all?(apns_vars, &(&1 in [nil, ""])) ->
        []

      Enum.any?(apns_vars, &(&1 in [nil, ""])) ->
        IO.puts(
          :stderr,
          "[push] APNs needs all of APNS_PRIVATE_KEY, APNS_KEY_ID, APNS_TEAM_ID and APNS_TOPIC — " <>
            "APNs disabled, deliveries fall back to the Log provider"
        )

        []

      not String.contains?(apns_key, "PRIVATE KEY") ->
        IO.puts(
          :stderr,
          "[push] APNS_PRIVATE_KEY does not look like .p8 key contents (or a path to them) — " <>
            "APNs disabled, deliveries fall back to the Log provider"
        )

        []

      true ->
        [
          {:gamend_core, Gamend.Push.APNSDispatcher,
           [
             adapter: Pigeon.APNS,
             key: apns_key,
             key_identifier: apns_key_id,
             team_id: apns_team_id,
             # `:apns_env` is an atom setting, so this compares atoms. It read
             # `== "sandbox"` against an atom value and was therefore never
             # true: every host talked to the production gateway, whatever it
             # configured.
             mode: if(setting.(Gamend.Push, :apns_env) == :sandbox, do: :dev, else: :prod)
           ]},
          {:gamend_core, Gamend.Push, [apns_topic: apns_topic]}
        ]
    end
  end

  # ── Declared settings ─────────────────────────────────────────────────────
  # Every setting declared with Gamend.Settings.Provider, read from the
  # environment once at boot.
  defp declared_settings_entries do
    Gamend.Settings.from_env()
  end

  # Outside prod the cache topology comes from the compiled config; honor the
  # GAMEND_CACHE_ENABLED toggle here so disabling it in dev/test isn't a
  # silent no-op. Only turning it off is copied across: the setting defaults
  # to on, and writing `bypass_mode: false` for that default overrode the
  # `bypass_mode: true` every test config sets, so suites ran cached.
  defp cache_bypass_entries(:prod, _setting), do: []

  defp cache_bypass_entries(_env, setting) do
    if setting.(Gamend.Cache.Settings, :enabled) do
      []
    else
      [{:gamend_core, Gamend.Cache, [bypass_mode: true]}]
    end
  end

  defp prod_entries(env, setting, host, scheme, host_root)

  defp prod_entries(env, _setting, _host, _scheme, _host_root) when env != :prod, do: []

  defp prod_entries(:prod, setting, host, scheme, host_root) do
    cache_entries(setting) ++
      [
        {:gamend_web, GamendWeb.Endpoint,
         [access_log: Gamend.Settings.get(GamendWeb.Observability, :access_log_level)]}
      ] ++
      repo_entries(setting, host_root) ++
      auth_entries(setting) ++
      [{:gamend_web, :dns_cluster_query, setting.(Gamend.Cluster, :dns_query)}] ++
      cors_and_endpoint_entries(setting, host, scheme) ++
      rate_limit_entries(setting) ++
      geoip_entries(setting, host_root)
  end

  defp cache_entries(setting) do
    cache_enabled = setting.(Gamend.Cache.Settings, :enabled)
    cache_mode = setting.(Gamend.Cache.Settings, :mode)
    cache_l2 = setting.(Gamend.Cache.Settings, :l2)

    redis_conn_opts =
      case setting.(Gamend.Cache.Settings, :redis_url) ||
             setting.(Gamend.Cluster, :redis_url) do
        nil -> []
        url -> redis_conn_opts_from_url(url)
      end

    local_opts = [
      # Create new generation every 12 hours
      gc_interval: :timer.hours(12),
      max_size: setting.(Gamend.Cache.Settings, :max_entries),
      allocated_memory: setting.(Gamend.Cache.Settings, :max_memory_mb) * 1_000_000,
      # Run size and memory checks every 10 seconds
      gc_memory_check_interval: :timer.seconds(10)
    ]

    levels =
      case cache_mode do
        :single ->
          [{Gamend.Cache.L1, local_opts}]

        _ ->
          l2_level =
            case cache_l2 do
              :redis ->
                pool_size = setting.(Gamend.Cache.Settings, :redis_pool_size)

                if redis_conn_opts == [] do
                  raise "GAMEND_CACHE_MODE=multi with GAMEND_CACHE_L2=redis requires GAMEND_CACHE_REDIS_URL or REDIS_URL"
                end

                {Gamend.Cache.L2.Redis, pool_size: pool_size, conn_opts: redis_conn_opts}

              _ ->
                # Partitioned uses a local primary storage on each node.
                {Gamend.Cache.L2.Partitioned, primary: local_opts}
            end

          [{Gamend.Cache.L1, local_opts}, l2_level]
      end

    [
      {:gamend_core, Gamend.Cache,
       [bypass_mode: not cache_enabled, inclusion_policy: :inclusive, levels: levels]}
    ]
  end

  defp redis_conn_opts_from_url(url) do
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
    |> then(fn opts -> if password, do: Keyword.put(opts, :password, password), else: opts end)
    |> then(fn opts ->
      if database != nil, do: Keyword.put(opts, :database, database), else: opts
    end)
  end

  defp repo_entries(setting, host_root) do
    # Check if PostgreSQL environment variables are set
    has_postgres_config =
      setting.(Gamend.Database, :url) ||
        (setting.(Gamend.Database, :postgres_host) &&
           setting.(Gamend.Database, :postgres_user))

    # SQLite has one writer, so the useful pool size is 1: writes then queue in
    # the BEAM, first-come-first-served and effectively free, instead of racing
    # each other inside SQLite. Contending connections there fall into
    # `sqlite3_busy_timeout`'s backoff, which is neither fair nor FIFO — a
    # sleeping connection loses the lock to a newcomer and sleeps longer.
    #
    # Measured on the load-test harness (`stress/`, dev SQLite, concurrent
    # `POST /login/device`, each creating a user):
    #
    #   pool 10    2 concurrent  30ms · 3  340ms · 6  10-21s, some 500s
    #   pool  1    6 concurrent  44-66ms  · 12  38-94ms, no errors
    #
    # Reads are unaffected at these concurrencies (WAL, and most reads are
    # cache hits), so the pool costs nothing to shrink. The declared setting
    # still overrides this, and has no default of its own because the sensible
    # one depends on the adapter, which is only known here.
    default_pool_size = if has_postgres_config, do: 10, else: 1
    repo_pool_size = setting.(Gamend.Database, :pool_size) || default_pool_size

    # Backpressure/overload tuning:
    # - pool_timeout: how long a request waits for a DB connection checkout (ms)
    # - queue_target/queue_interval: DBConnection queueing algorithm (ms)
    # - timeout: query timeout (ms)
    # Increasing queue_target/interval makes requests wait longer (can
    # increase memory under load); prod defaults to forgiving backpressure.
    repo_pool_timeout = setting.(Gamend.Database, :pool_timeout_ms)
    repo_queue_target = setting.(Gamend.Database, :queue_target)
    repo_queue_interval = setting.(Gamend.Database, :queue_interval_ms)
    repo_query_timeout = setting.(Gamend.Database, :query_timeout_ms)

    if has_postgres_config do
      database_url =
        setting.(Gamend.Database, :url) ||
          "ecto://#{setting.(Gamend.Database, :postgres_user)}:#{setting.(Gamend.Database, :postgres_password)}@#{setting.(Gamend.Database, :postgres_host)}:#{setting.(Gamend.Database, :postgres_port)}/#{setting.(Gamend.Database, :postgres_db)}"

      # The setting is a declared :boolean, so it arrives cast — the old
      # `in ~w(true 1)` string comparison could never match it and silently
      # disabled IPv6 for everyone.
      maybe_ipv6 = if setting.(Gamend.Database, :ipv6), do: [:inet6], else: []

      # Sent in the connection's startup packet rather than as a `SET` after
      # connecting: there is then no window in which a query could commit
      # under the wrong durability, and a bad value fails the connection
      # loudly at boot instead of silently leaving the server default in
      # place. `synchronous_commit` is USERSET, so a session may raise it
      # again — which is exactly what `Gamend.Repo.durable_transaction/2`
      # does for payments.
      synchronous_commit = setting.(Gamend.Database, :postgres_synchronous_commit)

      [
        {:gamend_core, Gamend.Repo,
         [
           url: database_url,
           adapter: Ecto.Adapters.Postgres,
           pool_size: repo_pool_size,
           pool_timeout: repo_pool_timeout,
           queue_target: repo_queue_target,
           queue_interval: repo_queue_interval,
           timeout: repo_query_timeout,
           socket_options: maybe_ipv6,
           parameters: [synchronous_commit: to_string(synchronous_commit)]
         ]}
      ]
    else
      # Fallback to persistent SQLite when no PostgreSQL config. Use
      # GAMEND_DB_SQLITE_PATH if set (e.g. a mounted volume), otherwise
      # default to the host-local db directory. The `game_server` in the
      # filename predates the Gamend rename; renaming it orphans live databases.
      default_db_path = Path.expand("db/game_server_prod.db", host_root)

      db_path =
        case setting.(Gamend.Database, :sqlite_path) do
          nil ->
            File.mkdir_p!(Path.dirname(default_db_path))
            default_db_path

          override ->
            override
        end

      # The setting is a declared :atom, so it arrives cast — the old case on
      # "off"/"normal"/"full"/"extra" strings could never match and silently
      # forced :normal for every configured value.
      sqlite_synchronous =
        case setting.(Gamend.Database, :sqlite_synchronous) do
          value when value in [:off, :normal, :full, :extra] -> value
          _ -> :normal
        end

      sqlite_cache_size_kb = setting.(Gamend.Database, :sqlite_cache_size_kb)
      sqlite_busy_timeout_ms = setting.(Gamend.Database, :sqlite_busy_timeout_ms)
      sqlite_wal_autocheckpoint = setting.(Gamend.Database, :sqlite_wal_autocheckpoint)

      # Ensure Ecto/DBConnection timeout does not fire before SQLite's busy
      # timeout.
      sqlite_query_timeout = max(repo_query_timeout, sqlite_busy_timeout_ms + 5_000)

      [
        {:gamend_core, Gamend.Repo,
         [
           database: db_path,
           adapter: Ecto.Adapters.SQLite3,
           pool_size: repo_pool_size,
           pool_timeout: repo_pool_timeout,
           queue_target: repo_queue_target,
           queue_interval: repo_queue_interval,
           timeout: sqlite_query_timeout,
           # IMMEDIATE, not the DEFERRED default: a deferred transaction that
           # reads before it writes has to *upgrade* its lock, and SQLite
           # answers a contended upgrade with SQLITE_BUSY straight away —
           # `busy_timeout` only covers waiting for a lock, never upgrading
           # one. Read-modify-write paths (quest progress, wallets, KV)
           # crashed under concurrent logins because of it. Taking the write
           # lock up front means those waits honour the timeout.
           default_transaction_mode: :immediate,
           # Top-level options, not a `pragmas:` list — ecto_sqlite3 has no
           # such key and silently ignores it (leaving e.g. busy_timeout at
           # the 2000ms default). busy_timeout in particular must be the
           # option: exqlite sets it via NIF, and `PRAGMA busy_timeout` would
           # destroy its busy handler.
           foreign_keys: :on,
           journal_mode: :wal,
           synchronous: sqlite_synchronous,
           temp_store: :memory,
           cache_size: -sqlite_cache_size_kb,
           busy_timeout: sqlite_busy_timeout_ms,
           wal_auto_check_point: sqlite_wal_autocheckpoint
         ]}
      ]
    end
  end

  defp auth_entries(setting) do
    # The secret key base signs/encrypts cookies and other secrets. Declared
    # as `auth.secret_key_base` and enforced by Gamend.Settings.validate!/1
    # at boot, which reports every missing required setting at once.
    secret_key_base = setting.(Gamend.Accounts, :secret_key_base)

    # Guardian JWT secret — can be the same as secret_key_base or separate.
    guardian_secret_key =
      setting.(Gamend.Accounts, :guardian_secret_key) || secret_key_base

    # Token lifetimes are not here: GamendWeb.Auth.Guardian reads them from
    # the auth.*_token_ttl_* settings in every environment.
    [{:gamend_web, GamendWeb.Auth.Guardian, [issuer: "gamend", secret_key: guardian_secret_key]}]
  end

  defp rate_limit_entries(setting) do
    # Rate limiting is declared on GamendWeb.Plugs.RateLimiter and
    # GamendWeb.RateLimit; from_env/0 resolves it. The redis URL still
    # falls back to the shared cache URL when only that is set.
    if setting.(GamendWeb.RateLimit, :redis_url) in [nil, ""] do
      shared_redis =
        setting.(Gamend.Cache.Settings, :redis_url) ||
          setting.(Gamend.Cluster, :redis_url)

      if shared_redis in [nil, ""] do
        []
      else
        [{:gamend_web, GamendWeb.RateLimit, [redis_url: shared_redis]}]
      end
    else
      []
    end
  end

  # Bandit logs every malformed request it turns away at `:error`: a request
  # line with no HTTP version, a proxy-style `http://host/` target, a
  # `Connection:` header on an HTTP/2 stream, a body that ends before its
  # declared length. A listener bound straight to the internet gets those all
  # day from scanners — one bot produced a hundred in ninety seconds — and they
  # are noise by construction: a protocol error is the peer's fault, nothing
  # here can change to prevent the next one, and the line does not even name
  # the peer. They crowded real errors out of the admin log buffer.
  #
  # Off at the source rather than dropped afterwards in `GamendWeb.LogFilters`,
  # which would mean matching on Bandit's message strings. On both listeners.
  # A request that reaches the router and fails still logs exactly as before;
  # this covers only what never became a request.
  @bandit_http_options [log_protocol_errors: false]

  defp cors_and_endpoint_entries(setting, host, scheme) do
    secret_key_base = setting.(Gamend.Accounts, :secret_key_base)
    port = setting.(GamendWeb.Http, :port)

    # The origin allowlist arrives already split — it is a declared `:list`,
    # so nothing here has to parse a comma-separated string. An entry prefixed
    # with `regex:` compiles to a pattern; a bare host is normalised to the
    # protocol-agnostic `//host` form Phoenix and Corsica both accept.
    allowed_origins =
      Enum.map(setting.(GamendWeb.Http, :allowed_origins) || [], &normalize_origin/1)

    # nil lets Phoenix apply its own check_origin default; "*" is Corsica's
    # allow-any. Both mean "the operator did not restrict this".
    check_origin = if allowed_origins == [], do: nil, else: allowed_origins

    # Corsica needs a different shape from Phoenix for the same allowlist.
    # `check_origin` understands the protocol-agnostic `//host` form, but
    # Corsica compares binary origins with *exact equality* — `"//gamend.org"`
    # never equals `"https://gamend.org"`, so a configured allowlist silently
    # emitted no CORS headers at all. A regex per host matches either scheme and
    # is the form Corsica does understand.
    cors_allowed_origins =
      if allowed_origins == [], do: "*", else: Enum.map(allowed_origins, &to_cors_origin/1)

    endpoint_config =
      [
        url: [host: host, port: if(scheme == "https", do: 443, else: port), scheme: scheme],
        http: [
          # Enable IPv6 and bind on all interfaces. Set it to
          # {0, 0, 0, 0, 0, 0, 0, 1} for local network only access. See
          # https://hexdocs.pm/bandit/Bandit.html#t:options/0 for IPv6 vs
          # IPv4 and loopback vs public addresses.
          ip: {0, 0, 0, 0, 0, 0, 0, 0},
          port: port,
          http_options: @bandit_http_options,
          thousand_island_options: [
            transport_options: socket_buffer_options(setting)
          ]
        ],
        secret_key_base: secret_key_base
      ]
      |> then(fn cfg ->
        if check_origin == nil, do: cfg, else: Keyword.put(cfg, :check_origin, check_origin)
      end)
      |> put_https(setting)

    [
      # Expose these choices via application config so endpoint/plug can pick
      # them up.
      {:gamend_web, :cors_allowed_origins, cors_allowed_origins},
      # `acme_entries/1` sets `:acme_webroot`, a different key, so trailing it
      # here does not shadow the endpoint config.
      {:gamend_web, GamendWeb.Endpoint, endpoint_config}
    ] ++ acme_entries(setting)
  end

  # A regex passes through; `//host` becomes a scheme-agnostic pattern; a fully
  # qualified origin is already exact and needs nothing.
  defp to_cors_origin(%Regex{} = regex), do: regex

  defp to_cors_origin("//" <> host),
    do: Regex.compile!("^https?://" <> Regex.escape(host) <> "$")

  defp to_cors_origin(origin), do: origin

  defp normalize_origin(<<"regex:", pattern::binary>>), do: Regex.compile!(pattern)

  defp normalize_origin(origin) do
    if String.starts_with?(origin, "//") or String.starts_with?(origin, "http") do
      origin
    else
      "//" <> origin
    end
  end

  # ── HTTPS / TLS ───────────────────────────────────────────────────────────
  # Native HTTPS in Phoenix/Bandit via GAMEND_TLS_CERTFILE / GAMEND_TLS_KEYFILE
  # (paths to fullchain.pem / privkey.pem). Erlang's :ssl reloads certificate
  # files from disk, so renewed certificates (e.g. from certbot) are picked up
  # without restart. GAMEND_TLS_PORT sets the HTTPS port; GAMEND_TLS_FORCE is
  # read per request by `GamendWeb.Plugs.ForceSSL`, not from here — Phoenix's
  # `:force_ssl` endpoint option is compile-time only, so configuring it in
  # this (runtime) file wrote a key nothing read and no redirect ever happened.
  # Only `buffer`, deliberately. It is the Erlang inet driver's own read buffer,
  # it lives in the emulator's binary memory, and it is the ~105 KB per idle
  # socket this exists to reclaim. `recbuf`/`sndbuf` are the *kernel's* buffers
  # and set the TCP window — shrinking those caps a connection's throughput at
  # window/RTT, which for the same listener that serves multi-megabyte Godot web
  # exports would be a bad trade for memory nobody was short of. The kernel
  # keeps sizing those; only the userspace copy is bounded.
  defp socket_buffer_options(setting) do
    case setting.(GamendWeb.Realtime, :socket_buffer_kb) do
      kb when is_integer(kb) and kb > 0 -> [buffer: kb * 1024]
      _leave_the_default -> []
    end
  end

  defp put_https(endpoint_config, setting) do
    if ssl_files_ready?(setting) do
      https_opts = [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: setting.(GamendWeb.Tls, :port),
        cipher_suite: :strong,
        certfile: setting.(GamendWeb.Tls, :certfile),
        keyfile: setting.(GamendWeb.Tls, :keyfile),
        http_options: @bandit_http_options,
        thousand_island_options: [
          # A public listener spends its day being probed. Both of these are
          # about connections that never became a request, and neither says
          # anything about this server:
          #
          #   * `silent_terminate_on_error` — the acceptor process stops
          #     without a crash report when the socket dies under it. The
          #     common one is a browser sending `user_canceled` and hanging up,
          #     which OTP reported as a `GenServer terminating` error complete
          #     with a full socket dump. Requests that fail still log: Bandit
          #     logs those itself, from a live connection.
          #   * `log_level: :error` — :ssl logs a `notice` per rejected
          #     handshake (SSLv2 hellos, unsupported groups, a plain-HTTP
          #     request to 443). Errors still come through.
          silent_terminate_on_error: true,
          transport_options: [log_level: :error]
        ]
      ]

      Keyword.put(endpoint_config, :https, https_opts)
    else
      endpoint_config
    end
  end

  # Validate that certificate files actually exist before enabling HTTPS.
  # This prevents a crash on startup when the TLS vars are set but the files
  # haven't been created yet (e.g. before running certbot).
  defp ssl_files_ready?(setting) do
    ssl_certfile = setting.(GamendWeb.Tls, :certfile)
    ssl_keyfile = setting.(GamendWeb.Tls, :keyfile)

    if ssl_certfile && ssl_keyfile do
      cert_exists? = File.exists?(ssl_certfile)
      key_exists? = File.exists?(ssl_keyfile)

      unless cert_exists? do
        Logger.warning(
          "GAMEND_TLS_CERTFILE is set to #{ssl_certfile} but the file does not exist. " <>
            "HTTPS will NOT be enabled. Run certbot to generate the certificate first, " <>
            "then restart the server."
        )
      end

      unless key_exists? do
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
  end

  # ACME webroot for Let's Encrypt HTTP-01 validation. Certbot writes
  # challenge tokens to <webroot>/.well-known/acme-challenge/<token>; the
  # AcmeChallenge plug serves them over HTTP so the CA can verify domain
  # ownership. Enabled whenever GAMEND_TLS_CERTFILE is set (even if the file
  # doesn't exist yet) so certbot can complete its first challenge.
  defp acme_entries(setting) do
    acme_webroot =
      setting.(GamendWeb.Tls, :acme_webroot) ||
        if(setting.(GamendWeb.Tls, :certfile), do: "/var/www/acme")

    cond do
      is_nil(acme_webroot) ->
        []

      acme_dir_ready?(acme_webroot) ->
        [{:gamend_web, :acme_webroot, acme_webroot}]

      true ->
        []
    end
  end

  # Ensure the ACME webroot directory exists; try to create it so certbot can
  # write challenge tokens before its first run. If creation fails (e.g.
  # permission denied), log a warning and skip the config so the server
  # doesn't emit confusing errors when serving challenge requests.
  defp acme_dir_ready?(acme_webroot) do
    if File.dir?(acme_webroot) do
      true
    else
      case File.mkdir_p(acme_webroot) do
        :ok ->
          true

        {:error, reason} ->
          Logger.warning(
            "ACME webroot directory #{acme_webroot} does not exist and could not be created " <>
              "(#{reason}). ACME HTTP-01 challenges will not be served. " <>
              "Create the directory manually: sudo mkdir -p #{acme_webroot}"
          )

          false
      end
    end
  end

  # ── GeoIP database ────────────────────────────────────────────────────────
  # Prefer the host-owned default path under data/, but still allow
  # GAMEND_CONTENT_GEOIP_DB_PATH to override it for custom deployments.
  defp geoip_entries(setting, host_root) do
    default_geoip_db = Path.expand("data/GeoLite2-Country.mmdb", host_root)

    geoip_db =
      setting.(Gamend.ContentSettings, :geoip_db_path) ||
        if File.exists?(default_geoip_db), do: default_geoip_db, else: nil

    if geoip_db do
      [
        {:geolix,
         [
           databases: [
             %{
               id: :country,
               adapter: Geolix.Adapter.MMDB2,
               source: geoip_db
             }
           ]
         ]}
      ]
    else
      []
    end
  end
end
