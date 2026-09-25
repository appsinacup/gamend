defmodule Gamend.RuntimeConfigTest do
  @moduledoc """
  Evaluates `config/host_runtime.exs` the way a real boot does, in `:prod`,
  with an environment complete enough to enter every branch.

  This file is the half of the settings layer that declarations cannot check:
  it turns typed settings into the shapes Phoenix, Ecto, Bandit, Swoosh and
  Pigeon expect. Nothing else covers it — the suite runs in `:test`, and the
  interesting derivations are behind `if config_env() == :prod` or behind "is
  SMTP configured", so they never ran here.

  They should have. Two real crashes reached production from this file: a
  setting already cast to `:never` handed to `String.to_existing_atom/1`, and
  `cache_mode` matched against `"single"` after it became the atom `:single`,
  which silently built a partitioned multi-node cache for every single-instance
  deployment.
  """

  # async: false — sets OS environment variables.
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../../../config/host_runtime.exs", __DIR__)

  # Enough to enter the SMTP, cache, storage, APNs, TLS and Postgres branches.
  @full_env %{
    "GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64),
    "GAMEND_HTTP_HOST" => "example.com",
    "GAMEND_MAIL_SMTP_PASSWORD" => "smtp-password",
    "GAMEND_MAIL_SMTP_RELAY" => "smtp.example.com",
    "GAMEND_MAIL_SMTP_USERNAME" => "smtp-user",
    "GAMEND_CACHE_MODE" => "multi",
    "GAMEND_CACHE_L2" => "redis",
    "GAMEND_CACHE_REDIS_URL" => "redis://:secret@localhost:6380/3",
    "GAMEND_STORAGE_ADAPTER" => "s3",
    "GAMEND_STORAGE_BUCKET" => "uploads",
    "GAMEND_STORAGE_ACCESS_KEY_ID" => "key",
    "GAMEND_STORAGE_SECRET_ACCESS_KEY" => "secret",
    "GAMEND_RATELIMIT_BACKEND" => "redis",
    "GAMEND_RATELIMIT_REDIS_URL" => "redis://localhost:6379",
    "GAMEND_OBSERVABILITY_LOG_LEVEL" => "warning",
    "GAMEND_HTTP_ALLOWED_ORIGINS" => "//game.example.com,regex:^https://(.+\\.)?itch\\.io$",
    "GAMEND_DB_URL" => "ecto://user:pass@db.example.com:5432/game",
    "GAMEND_HTTP_PORT" => "8080"
  }

  setup context do
    env = Map.get(context, :env, @full_env)
    previous = Map.new(env, fn {key, _} -> {key, System.get_env(key)} end)
    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    %{config: Config.Reader.read!(@runtime_config, env: :prod)}
  end

  describe "mailer" do
    test "hands Swoosh the types gen_smtp expects, not strings", %{config: config} do
      mailer = config[:gamend_core][Gamend.Mailer]

      assert mailer[:adapter] == Swoosh.Adapters.SMTP
      assert mailer[:relay] == "smtp.example.com"
      assert mailer[:username] == "smtp-user"

      # The crash: these are declared as an atom and a boolean, and were being
      # passed through String.to_existing_atom/1.
      assert is_atom(mailer[:tls]) and mailer[:tls] == :never
      assert is_boolean(mailer[:ssl])
      assert is_integer(mailer[:port])
    end

    test "server_name_indication is a charlist, which gen_smtp requires", %{config: config} do
      sni = config[:gamend_core][Gamend.Mailer][:sockopts][:server_name_indication]

      assert is_list(sni)
      assert to_string(sni) == "smtp.example.com"
    end

    @tag env: %{"GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64)}
    test "falls back to the local mailbox when no password is set", %{config: config} do
      assert config[:gamend_core][Gamend.Mailer][:adapter] == Swoosh.Adapters.Local
    end
  end

  describe "cache topology" do
    test "multi + redis builds an L1 and a Redis L2", %{config: config} do
      levels = config[:gamend_core][Gamend.Cache][:levels]

      assert [{Gamend.Cache.L1, _}, {Gamend.Cache.L2.Redis, redis_opts}] = levels
      assert redis_opts[:conn_opts][:host] == "localhost"
      assert redis_opts[:conn_opts][:port] == 6380
      assert redis_opts[:conn_opts][:database] == 3
      assert redis_opts[:conn_opts][:password] == "secret"
    end

    # The second crash: `:single` never matched `"single"`, so the default
    # single-instance deployment silently got a partitioned multi-node cache.
    @tag env: %{"GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64)}
    test "the default is a single local level, not a partitioned cluster", %{config: config} do
      levels = config[:gamend_core][Gamend.Cache][:levels]

      assert [{Gamend.Cache.L1, _}] = levels
    end

    @tag env: %{
           "GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64),
           "GAMEND_CACHE_MODE" => "multi"
         }
    test "multi without an L2 choice uses the partitioned level", %{config: config} do
      levels = config[:gamend_core][Gamend.Cache][:levels]

      assert [{Gamend.Cache.L1, _}, {Gamend.Cache.L2.Partitioned, _}] = levels
    end

    @tag env: %{
           "GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64),
           "GAMEND_CACHE_MODE" => "multi",
           "GAMEND_CACHE_MAX_ENTRIES" => "5000",
           "GAMEND_CACHE_MAX_MEMORY_MB" => "64"
         }
    test "each node's local cache is sized by the settings", %{config: config} do
      levels = config[:gamend_core][Gamend.Cache][:levels]

      assert [{Gamend.Cache.L1, l1}, {Gamend.Cache.L2.Partitioned, l2}] = levels

      for opts <- [l1, l2[:primary]] do
        assert opts[:max_size] == 5_000
        assert opts[:allocated_memory] == 64_000_000
      end
    end
  end

  # Outside prod the compiled config owns the cache; the toggle may only turn
  # it off. Copying the default "on" across overrode every test config's
  # `bypass_mode: true`.
  describe "cache outside prod" do
    @tag env: %{"GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64)}
    test "leaves the compiled bypass alone while the cache is on" do
      config = Config.Reader.read!(@runtime_config, env: :test)

      refute Keyword.has_key?(config[:gamend_core][Gamend.Cache] || [], :bypass_mode)
    end

    @tag env: %{
           "GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64),
           "GAMEND_CACHE_ENABLED" => "false"
         }
    test "bypasses the cache when it is turned off" do
      config = Config.Reader.read!(@runtime_config, env: :test)

      assert config[:gamend_core][Gamend.Cache][:bypass_mode] == true
    end
  end

  describe "endpoint" do
    test "url, port and origins take their shapes from the settings", %{config: config} do
      endpoint = config[:gamend_web][GamendWeb.Endpoint]

      assert endpoint[:url][:host] == "example.com"
      assert endpoint[:url][:scheme] == "https"
      assert endpoint[:http][:port] == 8080
      assert is_binary(endpoint[:secret_key_base])
    end

    test "a regex: origin compiles, and a bare host is made protocol-agnostic", %{config: config} do
      origins = config[:gamend_web][GamendWeb.Endpoint][:check_origin]

      assert "//game.example.com" in origins
      assert Enum.any?(origins, &match?(%Regex{}, &1))
    end
  end

  describe "repo" do
    test "uses the provisioned GAMEND_DB_URL with integer pool settings", %{config: config} do
      repo = config[:gamend_core][Gamend.Repo]

      assert repo[:url] == "ecto://user:pass@db.example.com:5432/game"
      assert repo[:adapter] == Ecto.Adapters.Postgres
      assert is_integer(repo[:pool_size])
      assert is_integer(repo[:timeout])
    end

    # SQLite options must be top-level repo options: ecto_sqlite3 has no
    # `pragmas:` key and silently ignored one for months, leaving prod at the
    # 2000ms default busy timeout while GAMEND_DB_SQLITE_BUSY_TIMEOUT_MS
    # appeared configurable. The synchronous setting is a declared :atom — a
    # case on "off"/"full" strings never matched and forced :normal.
    @tag env: %{
           "GAMEND_DB_URL" => "",
           # Cleared explicitly: when the suite itself runs against Postgres
           # (CI's test-postgres job) these are set in the ambient env and
           # would flip the built config away from the SQLite branch.
           "GAMEND_DB_POSTGRES_HOST" => "",
           "GAMEND_DB_POSTGRES_USER" => "",
           "GAMEND_AUTH_SECRET_KEY_BASE" => String.duplicate("a", 64),
           "GAMEND_DB_SQLITE_PATH" => "/tmp/runtime_config_test.db",
           "GAMEND_DB_SQLITE_BUSY_TIMEOUT_MS" => "7000",
           "GAMEND_DB_SQLITE_SYNCHRONOUS" => "full"
         }
    test "sqlite settings land as top-level options the adapter reads", %{config: config} do
      repo = config[:gamend_core][Gamend.Repo]

      assert repo[:adapter] == Ecto.Adapters.SQLite3
      assert repo[:database] == "/tmp/runtime_config_test.db"
      assert repo[:default_transaction_mode] == :immediate
      assert repo[:journal_mode] == :wal
      assert repo[:busy_timeout] == 7000
      assert repo[:synchronous] == :full
      refute Keyword.has_key?(repo, :pragmas)
      # DBConnection's query timeout must outlast the busy wait.
      assert repo[:timeout] >= repo[:busy_timeout] + 5_000
    end
  end

  describe "storage and rate limiting" do
    test "s3 credentials reach the adapter's own config", %{config: config} do
      assert config[:gamend_core][Gamend.Storage][:adapter] == :s3

      s3 = config[:gamend_core][Gamend.Storage.S3]
      assert s3[:bucket] == "uploads"
      assert s3[:access_key_id] == "key"
    end

    test "the redis backend is selected with its url", %{config: config} do
      rate_limit = config[:gamend_web][GamendWeb.RateLimit]

      assert rate_limit[:backend] == :redis
      assert rate_limit[:redis_url] == "redis://localhost:6379"
    end
  end

  describe "logger" do
    test "the declared level is mirrored onto :logger as an atom", %{config: config} do
      assert config[:logger][:level] == :warning
    end
  end
end
