defmodule GameServerHost.Application do
  @moduledoc false

  use Application

  alias GameServer.Hooks.PluginManager
  alias GameServer.Repo.AdvisoryLock

  @impl true
  def start(_type, _args) do
    GameServerWeb.HostSupervision.init_runtime()
    GameServerHost.ContentPaths.register_defaults()

    children = GameServerWeb.HostSupervision.children()

    opts = [strategy: :one_for_one, name: GameServerHost.Supervisor]

    result = Supervisor.start_link(children, opts)

    log_startup_resources()

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    GameServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp log_startup_resources do
    require Logger

    lines = [
      "=== GameServer startup resources ===",
      database_info(),
      cache_info(),
      mailer_info(),
      jwt_info(),
      oauth_info(),
      clustering_info(),
      plugins_info(),
      channels_info(),
      endpoint_info()
    ]

    Logger.info(Enum.join(lines, "\n  "))
  end

  defp database_info do
    repo_config = GameServer.Repo.config()

    adapter_name = GameServer.Repo.__adapter__() |> inspect() |> String.split(".") |> List.last()

    mismatch =
      if AdvisoryLock.postgres?() == false &&
           (System.get_env("GAMEND_DB_URL") ||
              (System.get_env("GAMEND_DB_POSTGRES_HOST") &&
                 System.get_env("GAMEND_DB_POSTGRES_USER"))) do
        " [WARNING: Postgres env vars set but compiled with SQLite — dev: mix deps.clean game_server_core game_server_web --build, then recompile; Docker: use the -postgres image tag or build with DATABASE_ADAPTER=postgres]"
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
    cache_config = Application.get_env(:game_server_core, GameServer.Cache, [])
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
    mailer_config = Application.get_env(:game_server_core, GameServer.Mailer, [])
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

  defp jwt_info do
    guardian_config =
      Application.get_env(:game_server_web, GameServerWeb.Auth.Guardian, [])

    ttl = guardian_config[:ttl]
    ttl_str = if ttl, do: "#{elem(ttl, 0)} #{elem(ttl, 1)}", else: "default"
    "JWT: Guardian (TTL: #{ttl_str})"
  end

  defp oauth_info do
    providers =
      [
        {"Discord", :discord_client_id},
        {"Apple", :apple_client_id},
        {"Google", :google_client_id},
        {"Facebook", :facebook_client_id},
        {"Steam", :steam_api_key}
      ]
      |> Enum.filter(fn {_name, key} ->
        GameServer.Settings.get(GameServer.OAuth.Providers, key) not in [nil, ""]
      end)
      |> Enum.map(fn {name, _} -> name end)

    if providers == [] do
      "OAuth: none configured"
    else
      "OAuth: #{Enum.join(providers, ", ")}"
    end
  end

  defp clustering_info do
    query = Application.get_env(:game_server_web, :dns_cluster_query)

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
    channels = GameServerWeb.UserSocket.__channels__()

    "Channels: #{length(channels)} (#{Enum.map_join(channels, ", ", fn {pattern, _mod, _desc} -> pattern end)})"
  end

  defp endpoint_info do
    endpoint_config = Application.get_env(:game_server_web, GameServerWeb.Endpoint, [])
    url_config = endpoint_config[:url] || []
    host = url_config[:host] || "localhost"
    port = get_in(endpoint_config, [:http, :port]) || 4000
    "Endpoint: #{host}:#{port}"
  end
end
