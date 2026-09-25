defmodule GamendHost.Application do
  @moduledoc false

  use Application

  alias Gamend.Hooks.PluginManager
  alias Gamend.OAuth.Providers
  alias Gamend.Repo.AdvisoryLock
  alias GamendWeb.Auth.Tokens

  @impl true
  def start(_type, _args) do
    GamendWeb.HostSupervision.init_runtime()
    GamendHost.ContentPaths.register_defaults()

    children = GamendWeb.HostSupervision.children()

    opts = [strategy: :one_for_one, name: GamendHost.Supervisor]

    result = Supervisor.start_link(children, opts)

    log_startup_resources()

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    GamendWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp log_startup_resources do
    require Logger

    lines = [
      "=== Gamend startup resources ===",
      database_info(),
      cache_info(),
      mailer_info(),
      jwt_info(),
      oauth_info(),
      clustering_info(),
      storage_info(),
      plugins_info(),
      channels_info(),
      endpoint_info()
    ]

    Logger.info(Enum.join(lines, "\n  "))
  end

  # Local storage inside the release is a trap: a deploy replaces that directory
  # and every uploaded or mirrored object goes with it, while the URLs stored in
  # the database keep pointing at files that no longer exist. Say so at boot
  # rather than letting it be discovered as an empty admin page months later.
  defp storage_info do
    adapter = Gamend.Storage.adapter() |> inspect() |> String.split(".") |> List.last()

    case adapter do
      "Local" ->
        dir = Gamend.Storage.Local.root_dir()

        "  Storage: local disk at #{dir}" <> ephemeral_warning(dir)

      other ->
        "  Storage: #{other}"
    end
  end

  defp ephemeral_warning(dir) do
    release? = System.get_env("RELEASE_NAME") != nil

    inside_release? =
      String.starts_with?(
        Path.expand(dir),
        Path.expand(to_string(:code.lib_dir(:gamend_core)))
      )

    if release? and (inside_release? or not absolute_and_outside_app?(dir)) do
      " [WARNING: this path is replaced on every deploy — stored objects will be" <>
        " lost. Set GAMEND_STORAGE_DIR to a mounted volume, or use the S3 adapter]"
    else
      ""
    end
  end

  # A relative path resolves against the release's working directory, which is
  # inside the image; only an absolute path can be a mounted volume.
  defp absolute_and_outside_app?(dir) do
    Path.type(dir) == :absolute and
      not String.starts_with?(dir, Path.expand(to_string(:code.root_dir())))
  end

  defp database_info do
    repo_config = Gamend.Repo.config()

    adapter_name = Gamend.Repo.__adapter__() |> inspect() |> String.split(".") |> List.last()

    mismatch =
      if AdvisoryLock.postgres?() == false &&
           (System.get_env("GAMEND_DB_URL") ||
              (System.get_env("GAMEND_DB_POSTGRES_HOST") &&
                 System.get_env("GAMEND_DB_POSTGRES_USER"))) do
        " [WARNING: Postgres env vars set but compiled with SQLite — dev: mix deps.clean gamend_core gamend_web --build, then recompile; Docker: use the -postgres image tag or build with DATABASE_ADAPTER=postgres]"
      else
        ""
      end

    db =
      cond do
        repo_config[:url] -> "(url configured)"
        repo_config[:database] -> repo_config[:database]
        true -> "(default)"
      end

    pool = repo_config[:pool_size] || "default"
    "Database: #{adapter_name} #{db} (pool: #{pool})#{mismatch}"
  end

  defp cache_info do
    cache_config = Application.get_env(:gamend_core, Gamend.Cache, [])
    bypass? = Keyword.get(cache_config, :bypass_mode, false)

    if bypass? do
      "Cache: disabled (bypass mode)"
    else
      l2_config = Keyword.get(cache_config, :l2, [])
      l2_adapter = Keyword.get(l2_config, :adapter)

      l2_name =
        case l2_adapter do
          NebulexRedisAdapter -> "Redis"
          Nebulex.Adapters.Partitioned -> "Partitioned"
          nil -> "L1 only"
          other -> inspect(other)
        end

      "Cache: enabled (L2: #{l2_name})"
    end
  end

  defp mailer_info do
    mailer_config = Application.get_env(:gamend_core, Gamend.Mailer, [])
    adapter = mailer_config[:adapter]

    case adapter do
      Swoosh.Adapters.SMTP ->
        relay = mailer_config[:relay] || "?"
        "Mailer: SMTP (#{relay})"

      Swoosh.Adapters.Local ->
        "Mailer: Local (in-memory, /dev/mailbox)"

      Swoosh.Adapters.Test ->
        "Mailer: Test adapter"

      nil ->
        "Mailer: not configured"

      other ->
        "Mailer: #{inspect(other)}"
    end
  end

  # The lifetimes are settings (`auth.*_token_ttl_*`), read through the same
  # function Guardian signs with, so the line says what tokens really get.
  defp jwt_info do
    %{"access" => {access, access_unit}, "refresh" => {refresh, refresh_unit}} =
      Tokens.ttls()

    "JWT: Guardian (access TTL: #{access} #{access_unit}, refresh TTL: #{refresh} #{refresh_unit})"
  end

  defp oauth_info do
    case Providers.enabled() do
      [] ->
        "OAuth: none configured"

      providers ->
        "OAuth: #{Enum.map_join(providers, ", ", &String.capitalize(Atom.to_string(&1)))}"
    end
  end

  defp clustering_info do
    query = Application.get_env(:gamend_web, :dns_cluster_query)

    if query && query != :ignore do
      "Clustering: DNS (#{query})"
    else
      node = Node.self()

      if node == :nonode@nohost do
        "Clustering: standalone (no distribution)"
      else
        "Clustering: node #{node}"
      end
    end
  end

  defp plugins_info do
    plugins = PluginManager.list()
    count = length(plugins)
    names = Enum.map(plugins, fn p -> p.name end)

    if count == 0 do
      "Plugins: none loaded"
    else
      "Plugins: #{count} loaded (#{Enum.join(names, ", ")})"
    end
  end

  defp channels_info do
    channels = GamendWeb.UserSocket.__channels__()

    "Channels: #{length(channels)} (#{Enum.map_join(channels, ", ", fn {pattern, _mod, _desc} -> pattern end)})"
  end

  defp endpoint_info do
    endpoint_config = Application.get_env(:gamend_web, GamendWeb.Endpoint, [])
    url_config = endpoint_config[:url] || []
    host = url_config[:host] || "localhost"
    port = get_in(endpoint_config, [:http, :port]) || 4000
    "Endpoint: #{host}:#{port}"
  end
end
