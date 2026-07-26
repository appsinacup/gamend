defmodule GameServerWeb.HostSupervision do
  @moduledoc """
  The canonical supervision tree for a GameServer host application.

  A host app owns its own `Application.start/2`, so historically it also owned a
  hand-written children list. That list is not host-specific — it is core's, and
  every core feature that adds a process needs a line in *every* host's copy.
  Nothing enforces that, and nothing fails loudly when it is missed: a missing
  child means enqueues target a process that was never started, so the feature
  silently no-ops while its config still reads "on".

  That is not hypothetical. Before this module existed, one host had drifted by
  six children (`Cache.Stats`, `Cache.Sync`, `IpBanSync`, `Retention`,
  `Tournaments.Ticker`, `Matchmaking.Worker`), an unbounded task supervisor, and
  the lobby-snapshots writer — the last of which cost a full debugging session
  to find, because every other signal said capture was working.

  So the list lives here, next to the features that populate it, and hosts call
  `children/1`. Host-specific processes go in `:extra` rather than into a fork
  of the list.

  ## Usage

      def start(_type, _args) do
        GameServerWeb.HostSupervision.init_runtime()

        Supervisor.start_link(
          GameServerWeb.HostSupervision.children(extra: [MyHost.Thing]),
          strategy: :one_for_one,
          name: MyHost.Supervisor
        )
      end
  """

  alias GameServerWeb.Plugs.GeoCountry
  alias GameServerWeb.Plugs.IpBan

  @doc """
  Set up the ETS tables and OS services children assume already exist.

  Must run before `children/1` is supervised: the Schedule tick reads the
  registry `GameServer.Schedule.start_link/0` creates, and the ban/geo plugs
  read theirs on the first request. Safe to call more than once.
  """
  @spec init_runtime() :: :ok
  def init_runtime do
    # Before anything starts: a missing required setting should stop the boot
    # here, with a list of what is missing, rather than surface later as a
    # crash-loop in whichever child needed it.
    GameServer.Settings.validate!(Application.get_env(:game_server_web, :environment, :prod))

    Application.start(:os_mon)

    # ETS owner for the Schedule registry + protected-callback set — must exist
    # before the Oban Cron tick fires.
    GameServer.Schedule.start_link()
    IpBan.init_table()
    GeoCountry.init_table()

    :ok
  end

  @doc """
  Core's children, in start order.

  Options:

  - `:plugins` — start `GameServer.Hooks.PluginManager` (default `true`). Hosts
    that ship no plugins, and test configs that load them separately, pass
    `false`.
  - `:extra` — host-specific children, appended after core's. Anything here is
    genuinely host-owned; if it is a core feature it belongs in this list
    instead, so every host gets it.

  Order matters and is deliberate: `Repo` and `Cache` before anything that
  reads them, `PluginManager` before `Endpoint` so hooks resolve on the first
  request, and the periodic workers last so a slow sweep never delays boot.
  """
  @spec children(keyword()) :: [Supervisor.child_spec() | {module(), term()} | module()]
  def children(opts \\ []) when is_list(opts) do
    plugins? = Keyword.get(opts, :plugins, true)
    extra = Keyword.get(opts, :extra, [])

    [
      GameServerWeb.Telemetry,
      GameServerWeb.PromEx,
      GameServer.Repo,
      {GameServer.Cache, []},
      # Aggregates cache hit/miss + overload counters for the admin dashboard
      GameServer.Cache.Stats,
      # Bounded: when full, GameServer.Async runs work inline (back-pressure)
      {Task.Supervisor, name: GameServer.TaskSupervisor, max_children: 200},
      {DNSCluster, query: Application.get_env(:game_server_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GameServer.PubSub},
      # Apply cache invalidations broadcast by other instances
      GameServer.Cache.Sync,
      GameServerWeb.ConnectionTracker,
      # Load persisted IP bans and mirror ban events from other instances
      GameServerWeb.IpBanSync,
      {GameServerWeb.RateLimit, clean_period: :timer.minutes(5)},
      GameServer.Lobbies.SpectatorTracker,
      GameServerWeb.AdminLogBuffer,
      # Periodic cleanup of old geo-country minute buckets
      GameServerWeb.GeoCountryCleaner
    ] ++
      plugin_children(plugins?) ++
      [
        GameServerWeb.Endpoint,
        # Periodically mark stale online users as offline (safety net for crashes)
        GameServer.Accounts.StalePresenceSweeper,
        # Prune old chat messages / notifications / payment events (RETENTION_* env vars)
        GameServer.Retention,
        # Tournament lifecycle: transitions, draws, match deadlines, recurrence
        GameServer.Tournaments.Ticker,
        # Push delivery processes (Goth + Pigeon dispatchers); supervises
        # nothing when no PUSH_*/APNS_* vars are set. Before Oban so
        # dispatchers are up when push-queue workers start running.
        GameServer.Push.Supervisor,
        # Durable background jobs (GameServer.Jobs) + the per-minute Cron tick
        # that drives GameServer.Schedule.
        {Oban, GameServer.Jobs.oban_config()},
        # Worker that drives the matchmaking sweep
        GameServer.Matchmaking.Worker,
        # Buffers lobby snapshots/events and assigns seq. :global-registered, so
        # only one node runs it and start_link returns :ignore on the others.
        GameServer.LobbySnapshots.Writer
      ] ++
      extra
  end

  # Load hook plugins (OTP apps) shipped under modules/plugins/*.
  defp plugin_children(true), do: [GameServer.Hooks.PluginManager]
  defp plugin_children(false), do: []
end
