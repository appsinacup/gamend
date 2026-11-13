defmodule GamendWeb.AdminLive.Index do
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.UserToken
  alias Gamend.Bans.Cache, as: BanCache
  alias Gamend.Chat.Reports
  alias Gamend.Groups
  alias Gamend.Hooks.PluginManager
  alias Gamend.KV
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Notifications
  alias Gamend.Parties
  alias Gamend.Payments
  alias Gamend.Repo
  alias GamendWeb.AdminLive.IndexCards
  alias GamendWeb.ConnectionTracker
  alias GamendWeb.Gettext.Stats, as: TranslationStats
  alias GamendWeb.Plugs.GeoCountry

  require Ecto.Query
  require Logger
  require Gamend.Groups.GroupType, as: GroupType
  require Gamend.Results.ResultStatus, as: ResultStatus
  require Gamend.Accounts.TokenContext, as: TokenContext

  @dev_routes? Application.compile_env(:gamend_web, :dev_routes, false)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.admin_header
          title="Admin Dashboard"
          icon="hero-squares-2x2-solid"
          color="primary"
          back={nil}
        >
          <:subtitle>System administration</:subtitle>
        </.admin_header>

        <%!-- The figures arrive once the socket is up (`load_stats/0`). --%>
        <div
          :if={!@stats_loaded?}
          id="admin-cards-loading"
          role="status"
          class="card bg-base-200 p-6 text-sm text-muted"
        >
          Counting the figures…
        </div>

        <div :if={@stats_loaded?} id="admin-cards" class="space-y-8">
          <%!-- Core's cards, from data (`IndexCards.sections/1`): each names
                its page in `GamendWeb.AdminLive.Pages` and says its lines. --%>
          <.admin_section :for={{title, cards} <- @sections} :key={title} title={title}>
            <.admin_card
              :for={card <- cards}
              :key={card.id}
              page={card.page}
              path={card[:path]}
              title={card[:title]}
              icon={card[:icon]}
              color={card[:color]}
              value={card[:value]}
              unit={card[:unit]}
              value_class={card[:value_class]}
            >
              <IndexCards.line :for={line <- card.lines} line={line} />
            </.admin_card>
          </.admin_section>

          <.admin_section :if={@host != []} title="This site">
            <.admin_card
              :for={card <- @host}
              title={card.title}
              path={card.path}
              icon={card[:icon]}
              color={card[:color]}
              value={card[:value]}
            >
              <IndexCards.line :for={line <- card[:lines] || []} line={line} />
            </.admin_card>
          </.admin_section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @stats_key {:admin_dashboard_stats}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_live_refresh()

    socket = socket |> assign(:stats_loaded?, false) |> assign_live_stats()

    # The figures are ~45 counts, and at a million rows they take a second or
    # more each. Read in `mount` they held the page, both renders, and up to 45
    # pooled connections at once; one that raised took the page down. So they
    # are read once the socket is up, four at a time (`load_stats/0`), and kept
    # for half a minute: within it, both renders draw them at once.
    socket =
      case Gamend.Cache.fetch(@stats_key) do
        {:ok, stats} ->
          assign_stats(socket, stats)

        _miss ->
          if connected?(socket), do: start_async(socket, :stats, &load_stats/0), else: socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:stats, {:ok, stats}, socket), do: {:noreply, assign_stats(socket, stats)}

  def handle_async(:stats, {:exit, reason}, socket) do
    Logger.error("admin dashboard: the figures did not load: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "The figures could not be read. Reload to try again.")}
  end

  # In memory (ETS, GenServers): instant, read on every render.
  defp assign_live_stats(socket) do
    geo = GeoCountry.dashboard_stats()
    log_level_counts = safe_log_count_by_level()

    assign(socket,
      conn_stats: ConnectionTracker.cluster_counts(),
      sys_stats: ConnectionTracker.system_stats(),
      rate_stats: build_rate_limit_stats(),
      ip_ban_count: length(BanCache.list(:ip)),
      account_ban_count: length(BanCache.list(:account)),
      geo_stats: geo.stats_all,
      geo_total: geo.total_all,
      geo_total_1h: geo.total_1h,
      geo_stats_1h: geo.stats_1h,
      geo_crawlers_1h: geo.crawlers_1h,
      geoip_available?: GeoCountry.geoip_available?(),
      log_level_counts: log_level_counts,
      log_total_buffered: Enum.reduce(log_level_counts, 0, fn {_, v}, acc -> acc + v end),
      log_recent_errors: safe_log_recent_errors(),
      storage_info: safe_storage_info(),
      cache_stats: Gamend.Cache.Stats.snapshot(),
      dev_routes?: @dev_routes?
    )
  end

  defp assign_stats(socket, r) do
    assign(socket,
      stats_loaded?: true,
      snapshot: r.snapshot,
      users_count: r.snapshot.players.players_total,
      sessions_count: r.sessions_count,
      lobbies_count: r.snapshot.lobbies.lobbies_total,
      leaderboards_count: r.leaderboards_count,
      tournaments_count: r.snapshot.tournaments.tournaments |> Map.values() |> Enum.sum(),
      matchmaking_stats: r.matchmaking_stats,
      ready_check_stats: r.ready_check_stats,
      tournament_stats: r.snapshot.tournaments,
      kv_count: r.kv_count,
      kv_global: r.kv_global,
      kv_user: r.kv_count - r.kv_global,
      users_google: r.users_google,
      users_facebook: r.users_facebook,
      users_github: r.users_github,
      users_discord: r.users_discord,
      users_apple: r.users_apple,
      users_steam: r.users_steam,
      users_device: r.users_device,
      users_password: r.users_password,
      lobbies_hostless: r.lobbies_hostless,
      lobbies_hidden: r.lobbies_hidden,
      lobbies_locked: r.lobbies_locked,
      lobbies_passworded: r.lobbies_passworded,
      notifications_count: r.notifications_count,
      push_stats: r.push_stats,
      leaderboard_records: r.leaderboard_records,
      groups_count: r.groups_count,
      groups_public: r.groups_public,
      groups_private: r.groups_private,
      groups_hidden: r.groups_hidden,
      groups_members: r.groups_members,
      parties_count: r.parties_count,
      blacklist_count: r.blacklist_count,
      friends_count: r.friends_count,
      parties_members: r.parties_members,
      chat_count: r.chat_count,
      chat_senders: r.chat_senders,
      chat_silent: max(r.snapshot.players.players_total - r.chat_senders, 0),
      chat_by_lobby: Map.get(r.chat_by_type, "lobby", 0),
      chat_by_group: Map.get(r.chat_by_type, "group", 0),
      chat_by_friend: Map.get(r.chat_by_type, "friend", 0),
      open_reports: r.open_reports,
      content_reports: Map.get(r.report_counts, "open", 0),
      report_counts: r.report_counts,
      host: r.host,
      github_installations: r.github_installations,
      active_mutes: r.active_mutes,
      translation_stats: r.translation_stats,
      quest_stats: r.quest_stats,
      payments_stats: r.payments_stats,
      result_counts: r.result_counts,
      analytics_stats: r.analytics_stats,
      users_unactivated: r.users_unactivated,
      oban_stats: r.oban_stats,
      economy_stats: r.economy_stats,
      plugin_count: r.plugins.count,
      plugin_errors: r.plugins.errors
    )
    |> assign_sections()
  end

  # The cards read the figures and the live stats both: built again when
  # either moves, once the figures are in.
  defp assign_sections(%{assigns: %{stats_loaded?: true}} = socket),
    do: assign(socket, :sections, IndexCards.sections(socket.assigns))

  defp assign_sections(socket), do: socket

  # Four at a time, so the dashboard never holds more than four of the pool's
  # connections; each figure on its own, so one that raises or runs past 30 s
  # is logged and shows its default while the rest still draw.
  defp load_stats do
    Gamend.Cache.cached(@stats_key, [ttl: :timer.seconds(30)], fn ->
      queries = stat_queries()

      queries
      |> Task.async_stream(fn {key, _default, fun} -> read_stat(key, fun) end,
        max_concurrency: 4,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(queries)
      |> Map.new(fn
        {{:ok, {:ok, value}}, {key, _default, _fun}} ->
          {key, value}

        {{:ok, :error}, {key, default, _fun}} ->
          {key, default}

        {{:exit, reason}, {key, default, _fun}} ->
          Logger.warning("admin dashboard: #{key} did not finish: #{inspect(reason)}")
          {key, default}
      end)
    end)
  end

  defp read_stat(key, fun) do
    {:ok, fun.()}
  rescue
    error ->
      Logger.warning(
        "admin dashboard: #{key} failed\n" <> Exception.format(:error, error, __STACKTRACE__)
      )

      :error
  end

  # `{key, default, read}`: the default is what the card shows when the read fails.
  defp stat_queries do
    [
      # Players / lobbies / parties / quests / matchmaking / tournaments come
      # from the one cached composition every stats surface reads.
      {:snapshot, empty_snapshot(), &safe_snapshot/0},
      # Sessions only, as the page the button opens lists: every token context
      # (reset, confirm, API) made this read higher than that page ever showed.
      {:sessions_count, 0,
       fn ->
         Repo.aggregate(
           Ecto.Query.where(UserToken, [t], t.context == ^TokenContext.session()),
           :count
         )
       end},
      {:notifications_count, 0, &Notifications.count_all_notifications/0},
      {:push_stats, %{live: 0, disabled: 0, by_platform: []}, &Gamend.Push.token_stats/0},
      {:leaderboards_count, 0, fn -> Repo.aggregate(Leaderboard, :count) end},
      {:matchmaking_stats, %{queued: 0, matched: 0, cancelled: 0, queues: []},
       &Gamend.Matchmaking.stats/0},
      {:ready_check_stats, %{}, &Gamend.ReadyChecks.stats/0},
      {:kv_count, 0, fn -> KV.count_entries() end},
      {:kv_global, 0, fn -> KV.count_entries(global_only: true) end},
      {:users_google, 0, fn -> Accounts.count_users_with_provider(:google_id) end},
      {:users_facebook, 0, fn -> Accounts.count_users_with_provider(:facebook_id) end},
      {:users_github, 0, fn -> Accounts.count_users_with_provider(:github_id) end},
      {:users_discord, 0, fn -> Accounts.count_users_with_provider(:discord_id) end},
      {:users_apple, 0, fn -> Accounts.count_users_with_provider(:apple_id) end},
      {:users_steam, 0, fn -> Accounts.count_users_with_provider(:steam_id) end},
      {:users_device, 0, fn -> Accounts.count_users_with_provider(:device_id) end},
      {:users_password, 0, &Accounts.count_users_with_password/0},
      {:lobbies_hostless, 0, &Gamend.Lobbies.count_hostless_lobbies/0},
      {:lobbies_hidden, 0, &Gamend.Lobbies.count_hidden_lobbies/0},
      {:lobbies_locked, 0, &Gamend.Lobbies.count_locked_lobbies/0},
      {:lobbies_passworded, 0, &Gamend.Lobbies.count_passworded_lobbies/0},
      {:leaderboard_records, 0, &Gamend.Leaderboards.count_all_records/0},
      {:groups_count, 0, &Groups.count_all_groups/0},
      {:groups_public, 0, fn -> Groups.count_groups_by_type(GroupType.public()) end},
      {:groups_private, 0, fn -> Groups.count_groups_by_type(GroupType.private()) end},
      {:groups_hidden, 0, fn -> Groups.count_groups_by_type(GroupType.hidden()) end},
      {:groups_members, 0, &Groups.count_all_members/0},
      {:parties_count, 0, &Parties.count_all_parties/0},
      {:blacklist_count, 0, &Gamend.Friends.count_all_blocks/0},
      {:friends_count, 0, &Gamend.Friends.count_all_friendships/0},
      {:parties_members, 0, &Parties.count_all_party_members/0},
      {:chat_count, 0, &Gamend.Chat.count_all_messages/0},
      {:chat_senders, 0, &Gamend.Chat.count_unique_senders/0},
      {:chat_by_type, %{}, &Gamend.Chat.count_messages_by_type/0},
      {:open_reports, 0, &Reports.count_open_reports/0},
      {:report_counts, %{}, &Gamend.Reports.count_by_status/0},
      {:host, [], &GamendWeb.AdminCard.load/0},
      {:github_installations, 0, &Gamend.GitHub.count_all_installations/0},
      {:active_mutes, 0, fn -> Gamend.Chat.count_mutes(%{"active" => true}) end},
      {:quest_stats,
       %{
         definitions: 0,
         active_definitions: 0,
         completions_today: 0,
         claims_today: 0,
         claimable_now: 0
       }, &Gamend.Quests.dashboard_stats/0},
      {:payments_stats,
       %{
         purchases: 0,
         completed_purchases: 0,
         products: 0,
         provider_products: 0,
         active_entitlements: 0
       }, &Payments.admin_stats/0},
      {:translation_stats, [], &TranslationStats.all_completeness/0},
      {:users_unactivated, 0, &Accounts.count_unactivated_users/0},
      {:oban_stats, empty_oban_stats(), &safe_oban_stats/0},
      {:economy_stats, %{wallets: 0, ledger: 0}, &safe_economy_stats/0},
      {:analytics_stats, empty_analytics_stats(), &safe_analytics_stats/0},
      {:result_counts, %{total: 0, open: 0}, &safe_result_counts/0},
      {:plugins, %{count: 0, errors: 0},
       fn ->
         plugins = PluginManager.list()
         %{count: length(plugins), errors: Enum.count(plugins, &match?({:error, _}, &1.status))}
       end}
    ]
  end

  @impl true
  def handle_info(:refresh_live_stats, socket) do
    schedule_live_refresh()

    geo = GeoCountry.dashboard_stats()

    {:noreply,
     assign(socket,
       conn_stats: ConnectionTracker.cluster_counts(),
       sys_stats: ConnectionTracker.system_stats(),
       rate_stats: build_rate_limit_stats(),
       ip_ban_count: length(BanCache.list(:ip)),
       account_ban_count: length(BanCache.list(:account)),
       geo_stats: geo.stats_all,
       geo_total: geo.total_all,
       geo_total_1h: geo.total_1h,
       geo_stats_1h: geo.stats_1h,
       geo_crawlers_1h: geo.crawlers_1h,
       log_recent_errors: safe_log_recent_errors(),
       cache_stats: Gamend.Cache.Stats.snapshot()
     )
     |> assign_sections()}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp schedule_live_refresh, do: Process.send_after(self(), :refresh_live_stats, 5_000)

  defp build_rate_limit_stats do
    # Counter inspection only works for the ETS backend; with the Redis
    # backend the "Cache & limits" card (deny telemetry) covers this.
    case GamendWeb.RateLimit.backend() do
      GamendWeb.RateLimit.ETS -> build_rate_limit_stats(GamendWeb.RateLimit.ETS)
      _other -> %{limited: 0}
    end
  end

  # IP bans are not Hammer entries — they live in `Gamend.Bans.Cache`'s own
  # table, counted into `ip_ban_count` — so no "ip_ban:" key ever matched here.
  defp build_rate_limit_stats(table) do
    # The limits the plug enforces, not fallbacks of 10/120.
    auth_limit = Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, :auth_limit)
    general_limit = Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, :general_limit)

    :ets.tab2list(table)
    |> Enum.reduce(%{limited: 0}, fn
      {{key, _window}, count, _expiry}, acc when is_binary(key) ->
        case bucket_limit(key, auth_limit, general_limit) do
          nil -> acc
          limit when count >= limit -> %{acc | limited: acc.limited + 1}
          _limit -> acc
        end

      _, acc ->
        acc
    end)
  rescue
    _ -> %{limited: 0}
  end

  # The limit a rate-limiter bucket key counts against, or nil for a key that
  # is not a per-client bucket.
  defp bucket_limit("auth:" <> _, auth_limit, _general_limit), do: auth_limit
  defp bucket_limit("general:" <> _, _auth_limit, general_limit), do: general_limit
  defp bucket_limit(_key, _auth_limit, _general_limit), do: nil

  defp safe_log_count_by_level do
    GamendWeb.AdminLogBuffer.count_by_level()
  rescue
    _ -> %{}
  end

  defp safe_log_recent_errors do
    GamendWeb.AdminLogBuffer.count_recent_errors(3600)
  rescue
    _ -> 0
  end

  defp safe_economy_stats do
    %{wallets: Gamend.Economy.count_wallets(), ledger: Gamend.Economy.count_ledger()}
  rescue
    _ -> %{wallets: 0, ledger: 0}
  end

  defp safe_snapshot do
    Gamend.Analytics.snapshot()
  rescue
    _ ->
      %{
        players: Gamend.Accounts.player_stats(),
        activity: %{dau: 0, wau: 0, mau: 0, new_users_1d: 0, new_users_7d: 0, new_users_30d: 0},
        lobbies: Gamend.Lobbies.stats(),
        parties: Gamend.Parties.stats(),
        quests: Gamend.Quests.stats(),
        signaling: Gamend.Signaling.stats(),
        matchmaking: %{queued: 0, queues: []},
        tournaments: Gamend.Tournaments.stats()
      }
  end

  # The dashboard must render before the `user_activity_days` migration has
  # run on an upgraded host; missing table → zeros, not a crashed index.
  defp safe_analytics_stats do
    Gamend.Analytics.dashboard_stats()
  rescue
    _ -> empty_analytics_stats()
  end

  defp empty_analytics_stats do
    %{
      dau: 0,
      wau: 0,
      mau: 0,
      stickiness: nil,
      d1: nil,
      d7: nil,
      d30: nil,
      payers_30d: 0,
      conversion_30d: nil
    }
  end

  # What the cards read of `Gamend.Analytics.snapshot/0`, all zero: the
  # default when even `safe_snapshot/0`'s fallback fails.
  defp empty_snapshot do
    %{
      players: %{players_total: 0},
      activity: %{dau: 0, wau: 0, mau: 0, new_users_1d: 0, new_users_7d: 0, new_users_30d: 0},
      lobbies: %{lobbies_total: 0},
      tournaments: %{tournaments: %{}, entries: %{}, matches: %{open: 0, total: 0, overdue: 0}}
    }
  end

  defp safe_storage_info do
    case Gamend.Storage.adapter() do
      Gamend.Storage.S3 ->
        cfg = Application.get_env(:gamend_core, Gamend.Storage.S3, [])
        %{adapter: "S3", detail: cfg[:bucket] || "—"}

      _ ->
        cfg = Application.get_env(:gamend_core, Gamend.Storage.Local, [])
        %{adapter: "Local disk", detail: cfg[:dir] || "priv/storage"}
    end
  rescue
    _ -> %{adapter: "—", detail: "—"}
  end

  defp safe_oban_stats do
    import Ecto.Query, only: [from: 2]

    counts =
      from(j in Oban.Job, group_by: j.state, select: {j.state, count(j.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: counts |> Map.values() |> Enum.sum(),
      executing: Map.get(counts, "executing", 0),
      available: Map.get(counts, "available", 0),
      scheduled: Map.get(counts, "scheduled", 0),
      retryable: Map.get(counts, "retryable", 0)
    }
  rescue
    _ -> empty_oban_stats()
  end

  defp empty_oban_stats, do: %{total: 0, executing: 0, available: 0, scheduled: 0, retryable: 0}

  defp safe_result_counts do
    %{total: Gamend.Results.count(), open: Gamend.Results.count(%{status: ResultStatus.open()})}
  rescue
    _ -> %{total: 0, open: 0}
  end
end
