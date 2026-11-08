defmodule GamendWeb.AdminLive.Index do
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.UserToken
  alias Gamend.Bans.Cache, as: BanCache
  alias Gamend.Chat.Reports
  alias Gamend.Groups
  alias Gamend.KV
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Notifications
  alias Gamend.Parties
  alias Gamend.Payments
  alias Gamend.Repo
  alias GamendWeb.AdminLive.Pages
  alias GamendWeb.ConnectionTracker
  alias GamendWeb.Gettext.Stats, as: TranslationStats
  alias GamendWeb.Plugs.GeoCountry

  require Ecto.Query
  require Gamend.Groups.GroupType, as: GroupType
  require Gamend.Results.ResultStatus, as: ResultStatus
  require Gamend.Accounts.TokenContext, as: TokenContext

  @dev_routes? Application.compile_env(:gamend_web, :dev_routes, false)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.admin_header title="Admin Dashboard" icon="hero-squares-2x2" color="primary" back={nil}>
          <:subtitle>System administration</:subtitle>
        </.admin_header>

        <.admin_menu sections={menu_sections(@host_links)} counts={menu_counts(assigns)} />

        <section class="space-y-2">
          <.eyebrow tag="h2">Overview</.eyebrow>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            <.admin_card page="/admin/users" value={@users_count}>
              <div>With password: {@users_password}</div>
              <div>Google: {@users_google}</div>
              <div>Facebook: {@users_facebook}</div>
              <div>GitHub: {@users_github}</div>
              <div>Discord: {@users_discord}</div>
              <div>Apple: {@users_apple}</div>
              <div>Steam: {@users_steam}</div>
              <div>Device-linked: {@users_device}</div>
            </.admin_card>

            <.admin_card title="Registration" icon="hero-user-plus" color="emerald">
              <div class="font-semibold">Today: {@snapshot.activity.new_users_1d}</div>
              <div class="font-semibold mt-2">
                Last 7 days: {@snapshot.activity.new_users_7d}
              </div>
              <div class="font-semibold mt-2">
                Last 30 days: {@snapshot.activity.new_users_30d}
              </div>
              <%= if @users_unactivated > 0 do %>
                <div class="mt-3 pt-2 border-t border-base-300">
                  <.link
                    navigate={~p"/admin/users?filter=unactivated"}
                    class="inline-flex items-center gap-1.5 text-warning font-semibold hover:underline"
                  >
                    <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                    Pending activation: {@users_unactivated}
                  </.link>
                </div>
              <% end %>
            </.admin_card>

            <.admin_card page="/admin/sessions" value={@sessions_count}>
              <div>Signed-in browser sessions</div>
            </.admin_card>

            <.admin_card page="/admin/analytics" title="Activity" icon="hero-bolt">
              <div class="font-semibold">Today (DAU): {@snapshot.activity.dau}</div>
              <div class="font-semibold mt-2">Last 7 days (WAU): {@snapshot.activity.wau}</div>
              <div class="font-semibold mt-2">Last 30 days (MAU): {@snapshot.activity.mau}</div>
              <div class="mt-3 pt-2 border-t border-base-300">
                Stickiness: {pct(@analytics_stats.stickiness)}
              </div>
              <div>
                D1 / D7 / D30: {pct(@analytics_stats.d1)} / {pct(@analytics_stats.d7)} / {pct(
                  @analytics_stats.d30
                )}
              </div>
              <div>Payer conversion (30d): {pct(@analytics_stats.conversion_30d)}</div>
            </.admin_card>

            <.admin_card page="/admin/lobbies" value={@lobbies_count}>
              <div>Hostless: {@lobbies_hostless}</div>
              <div>Hidden: {@lobbies_hidden}</div>
              <div>Locked: {@lobbies_locked}</div>
              <div>With password: {@lobbies_passworded}</div>
            </.admin_card>

            <.admin_card page="/admin/leaderboards" value={@leaderboards_count}>
              <div>Scores total: {@leaderboard_records}</div>
            </.admin_card>

            <.admin_card page="/admin/tournaments" value={@tournaments_count}>
              <div>
                Running: {state_count(@tournament_stats.tournaments, "running")} · Registration: {state_count(
                  @tournament_stats.tournaments,
                  "registration"
                )}
              </div>
              <div>
                Scheduled: {state_count(@tournament_stats.tournaments, "scheduled")} · Finished: {state_count(
                  @tournament_stats.tournaments,
                  "finished"
                )}
              </div>
              <div>Participants: {entries_total(@tournament_stats.entries)}</div>
              <div>
                Still in: {state_count(@tournament_stats.entries, "active")} · Eliminated: {state_count(
                  @tournament_stats.entries,
                  "eliminated"
                )}
              </div>
              <div>
                Champions: {state_count(@tournament_stats.entries, "winner")} · Awaiting draw: {state_count(
                  @tournament_stats.entries,
                  "registered"
                )}
              </div>
              <div>
                Matches: {@tournament_stats.matches.open} open / {@tournament_stats.matches.total}
              </div>
              <div :if={@tournament_stats.matches.overdue > 0} class="text-warning">
                Past deadline: {@tournament_stats.matches.overdue}
              </div>
            </.admin_card>

            <.admin_card page="/admin/matchmaking" value={@matchmaking_stats.queued}>
              <div>In queue now: {@matchmaking_stats.queued}</div>
              <div>
                Matched: {@matchmaking_stats.matched} · Cancelled: {@matchmaking_stats.cancelled}
              </div>
              <div>Active queues: {length(@matchmaking_stats.queues)}</div>
              <div>
                Ready checks 24h: {Map.get(@ready_check_stats, "passed", 0)} passed · {Map.get(
                  @ready_check_stats,
                  "failed",
                  0
                )} failed
              </div>
            </.admin_card>

            <.admin_card page="/admin/groups" value={@groups_count}>
              <div>Public: {@groups_public}</div>
              <div>Private: {@groups_private}</div>
              <div>Hidden: {@groups_hidden}</div>
              <div>Total members: {@groups_members}</div>
            </.admin_card>

            <.admin_card page="/admin/parties" value={@parties_count}>
              <div>Total members: {@parties_members}</div>
            </.admin_card>

            <.admin_card page="/admin/friends" value={@friends_count}>
              <div>Friendships</div>
              <div>
                Blocks: <.link navigate={~p"/admin/blacklist"} class="link">{@blacklist_count}</.link>
              </div>
            </.admin_card>

            <.admin_card page="/admin/chat" value={@chat_count}>
              <div>Users who wrote: {@chat_senders}</div>
              <div>Users who never wrote: {@chat_silent}</div>
              <div>In lobbies: {@chat_by_lobby}</div>
              <div>In groups: {@chat_by_group}</div>
              <div>Friend DMs: {@chat_by_friend}</div>
            </.admin_card>

            <.admin_card page="/admin/chat/reports" title="Chat moderation" value={@open_reports}>
              <div>Open reports</div>
              <div>
                Active mutes:
                <.link navigate={~p"/admin/bans?kind=chat"} class="link">{@active_mutes}</.link>
              </div>
              <div>
                <.link navigate={~p"/admin/chat/filter"} class="link">Word filter</.link>
              </div>
            </.admin_card>

            <.admin_card page="/admin/reports" value={@content_reports}>
              <div>Open reports</div>
              <div>Fixed: {Map.get(@report_counts, "fixed", 0)}</div>
              <div>Won't fix: {Map.get(@report_counts, "wontfix", 0)}</div>
              <div>Duplicate: {Map.get(@report_counts, "duplicate", 0)}</div>
            </.admin_card>

            <.admin_card
              page="/admin/translations"
              value={ngettext("%{count} language", "%{count} languages", length(@translation_stats))}
            >
              <div :for={stats <- @translation_stats} class="flex items-center gap-2">
                <span class="font-mono font-semibold w-6">{String.upcase(stats.locale)}</span>
                <div class="flex-1 bg-base-300 rounded-full h-1.5">
                  <div
                    class={[
                      "h-1.5 rounded-full transition-all",
                      if(stats.percent == 100.0, do: "bg-success", else: "bg-warning")
                    ]}
                    style={"width: #{stats.percent}%"}
                  >
                  </div>
                </div>
                <span class="font-mono text-xs w-10 text-right">{stats.percent}%</span>
              </div>
            </.admin_card>

            <.admin_card page="/admin/kv" value={@kv_count}>
              <div>Global entries: {@kv_global}</div>
              <div>User entries: {@kv_user}</div>
            </.admin_card>

            <.admin_card page="/admin/quests" value={@quest_stats.definitions}>
              <div>Active: {@quest_stats.active_definitions}</div>
              <div>Completions today: {@quest_stats.completions_today}</div>
              <div>Claims today: {@quest_stats.claims_today}</div>
              <div>Claimable now: {@quest_stats.claimable_now}</div>
            </.admin_card>

            <.admin_card page="/admin/notifications" value={@notifications_count}>
              <div>In-app notifications stored</div>
            </.admin_card>

            <.admin_card page="/admin/push" value={@push_stats.live}>
              <div>Disabled: {@push_stats.disabled}</div>
              <div :for={{platform, n} <- @push_stats.by_platform}>{platform}: {n}</div>
            </.admin_card>

            <.admin_card page="/admin/connections" value={@conn_stats.total_connections}>
              <div>WS sockets: {@conn_stats.ws_sockets}</div>
              <div>WS channels: {@conn_stats.total_channels}</div>
              <div>LiveViews: {@conn_stats.live_views}</div>
              <div>WebRTC: {@conn_stats.webrtc_peers}</div>
            </.admin_card>

            <.admin_card
              page="/admin/system"
              value={GamendWeb.ConnectionTracker.format_uptime(@sys_stats.uptime_seconds)}
            >
              <div>OTP: {@sys_stats.otp_release}</div>
              <div>Schedulers: {@sys_stats.schedulers}</div>
              <div>Node: {@sys_stats.node}</div>
              <div>
                Cluster: {ngettext("%{count} node", "%{count} nodes", @sys_stats.cluster_size)}
              </div>
              <div>Memory: {@sys_stats.memory_total_mb} MB</div>
              <div>
                Processes: {@sys_stats.process_count} / {format_number(@sys_stats.process_limit)}
              </div>
            </.admin_card>

            <.admin_card page="/admin/rate_limiting">
              <div class="flex justify-between items-center">
                <span>Active IP bans</span>
                <span class={[
                  "badge badge-sm font-mono",
                  if(@ip_ban_count > 0, do: "badge-error", else: "badge-ghost opacity-50")
                ]}>
                  {@ip_ban_count}
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span>Rate Limited (1m)</span>
                <span class={[
                  "badge badge-sm font-mono",
                  if(@rate_stats.limited > 0, do: "badge-warning", else: "badge-ghost opacity-50")
                ]}>
                  {@rate_stats.limited}
                </span>
              </div>
            </.admin_card>

            <.admin_card page="/admin/bans">
              <div class="flex justify-between items-center">
                <span>Banned accounts</span>
                <span class={[
                  "badge badge-sm font-mono",
                  if(@account_ban_count > 0, do: "badge-error", else: "badge-ghost opacity-50")
                ]}>
                  {@account_ban_count}
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span>Banned IPs</span>
                <span class={[
                  "badge badge-sm font-mono",
                  if(@ip_ban_count > 0, do: "badge-error", else: "badge-ghost opacity-50")
                ]}>
                  {@ip_ban_count}
                </span>
              </div>
            </.admin_card>

            <.admin_card page="/admin/geo" value={format_number(@geo_total)}>
              <div>
                {countries_label(length(@geo_stats))} &middot; {if(@geoip_available?,
                  do: "MMDB",
                  else: "CF header"
                )}
              </div>
              <div class="flex justify-between items-center">
                <span>Last hour</span>
                <span class="font-mono font-semibold">
                  {format_number(@geo_total_1h)} reqs &middot; {countries_label(length(@geo_stats_1h))}
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span>Crawlers, last hour</span>
                <span class="font-mono font-semibold">
                  {format_number(@geo_crawlers_1h)} &middot; {if(@geo_total_1h > 0,
                    do: round(@geo_crawlers_1h / @geo_total_1h * 100),
                    else: 0
                  )}%
                </span>
              </div>
              <%= for {country, count} <- Enum.take(@geo_stats_1h, 3) do %>
                <div class="flex justify-between items-center">
                  <span class="font-mono">{GamendWeb.AdminLive.Shared.country_flag(country)} {country}</span>
                  <span class="font-mono">{format_number(count)} (1h)</span>
                </div>
              <% end %>
              <div :if={length(@geo_stats_1h) > 3} class="text-center opacity-50">
                +{length(@geo_stats_1h) - 3} more
              </div>
            </.admin_card>

            <.admin_card page="/admin/results" value={@result_counts.total} unit="plays">
              <div class="flex justify-between">
                <span>Open</span>
                <span class="font-mono">{@result_counts.open}</span>
              </div>
            </.admin_card>

            <.admin_card
              page="/admin/logs"
              value={@log_recent_errors}
              unit="errors (1h)"
              value_class={if(@log_recent_errors > 0, do: "text-error", else: "text-success")}
            >
              <div class="flex justify-between">
                <span>Buffered</span>
                <span class="font-mono">{@log_total_buffered}</span>
              </div>
              <div :for={{level, count} <- @log_level_counts} class="flex justify-between">
                <span>{level}</span>
                <span class={[
                  "font-mono",
                  level == :error && "text-error",
                  level == :warning && "text-warning"
                ]}>
                  {count}
                </span>
              </div>
            </.admin_card>

            <.admin_card
              page="/admin/oban"
              title="Background jobs"
              link_label="Dashboard"
              value={@oban_stats.total}
              unit="jobs"
            >
              <div class="flex justify-between">
                <span>Executing</span>
                <span class="font-mono">{@oban_stats.executing}</span>
              </div>
              <div class="flex justify-between">
                <span>Available</span>
                <span class="font-mono">{@oban_stats.available}</span>
              </div>
              <div class="flex justify-between">
                <span>Scheduled</span>
                <span class="font-mono">{@oban_stats.scheduled}</span>
              </div>
              <div class="flex justify-between">
                <span>Retryable</span>
                <span class={["font-mono", @oban_stats.retryable > 0 && "text-warning"]}>
                  {@oban_stats.retryable}
                </span>
              </div>
            </.admin_card>

            <.admin_card page="/admin/storage" link_label="Manage" value={@storage_info.adapter}>
              <div class="flex justify-between">
                <span>Target</span>
                <span class="font-mono truncate ml-2">{@storage_info.detail}</span>
              </div>
            </.admin_card>

            <.admin_card
              page="/admin/economy"
              link_label="Manage"
              value={@economy_stats.wallets}
              unit="wallets"
            >
              <div class="flex justify-between">
                <span>Ledger entries</span>
                <span class="font-mono">{@economy_stats.ledger}</span>
              </div>
            </.admin_card>

            <.admin_card page="/admin/payments" value={@payments_stats.purchases}>
              <div>Completed: {@payments_stats.completed_purchases}</div>
              <div>Products: {@payments_stats.products}</div>
              <div>Provider SKUs: {@payments_stats.provider_products}</div>
              <div>Active entitlements: {@payments_stats.active_entitlements}</div>
            </.admin_card>

            <.admin_card
              title="Cache & limits"
              icon="hero-bolt"
              color="lime"
              note="since boot"
              value={cache_hit_rate_label(@cache_stats)}
              unit="hit rate"
            >
              <div
                :for={row <- Enum.take(@cache_stats.cache, 6)}
                class="flex justify-between"
              >
                <span>{row.prefix}</span>
                <span class="font-mono">
                  {row.hits}/{row.hits + row.misses} ({round(row.hit_rate * 100)}%)
                </span>
              </div>
              <div class="flex justify-between border-t border-base-300 pt-1 mt-1">
                <span>Rate-limit denials</span>
                <span class="font-mono">
                  {@cache_stats.rate_limit_denies |> Map.values() |> Enum.sum()}
                </span>
              </div>
              <div class="flex justify-between">
                <span>Async overloads</span>
                <span class={[
                  "font-mono",
                  @cache_stats.async_overloads > 0 && "text-warning"
                ]}>
                  {@cache_stats.async_overloads}
                </span>
              </div>
            </.admin_card>

            <.admin_card
              :for={card <- @host_cards}
              title={card.title}
              path={card.path}
              icon={card[:icon]}
              color={card[:color]}
              value={card[:value]}
            >
              <div :for={line <- card[:lines] || []}>
                <%= case line do %>
                  <% text when is_binary(text) -> %>
                    {text}
                  <% {label, nil, path} -> %>
                    <.link navigate={path} class="link">{label}</.link>
                  <% {label, value, path} -> %>
                    {label}: <.link navigate={path} class="link">{value}</.link>
                  <% {label, value} -> %>
                    {label}: {value}
                <% end %>
              </div>
            </.admin_card>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # Fire all independent DB queries in parallel for fast mount. The page
    # renders twice per view (HTTP, then the socket), and at a million rows
    # these counts take a second or more, so the two share one run for half a
    # minute; the live block below refreshes on its own.
    r =
      Gamend.Cache.cached({:admin_dashboard_stats}, [ttl: :timer.seconds(30)], fn ->
        tasks = %{
          # Players / lobbies / parties / quests / matchmaking / tournaments come
          # from the one cached composition every stats surface reads.
          snapshot: Task.async(fn -> safe_snapshot() end),
          # Sessions only, as the page the button opens lists: every token context
          # (reset, confirm, API) made this read higher than that page ever showed.
          sessions_count:
            Task.async(fn ->
              Repo.aggregate(
                Ecto.Query.where(UserToken, [t], t.context == ^TokenContext.session()),
                :count
              )
            end),
          notifications_count: Task.async(fn -> Notifications.count_all_notifications() end),
          push_stats: Task.async(fn -> Gamend.Push.token_stats() end),
          leaderboards_count: Task.async(fn -> Repo.aggregate(Leaderboard, :count) end),
          matchmaking_stats: Task.async(fn -> Gamend.Matchmaking.stats() end),
          ready_check_stats: Task.async(fn -> Gamend.ReadyChecks.stats() end),
          kv_count: Task.async(fn -> KV.count_entries() end),
          kv_global: Task.async(fn -> KV.count_entries(global_only: true) end),
          users_google: Task.async(fn -> Accounts.count_users_with_provider(:google_id) end),
          users_facebook: Task.async(fn -> Accounts.count_users_with_provider(:facebook_id) end),
          users_github: Task.async(fn -> Accounts.count_users_with_provider(:github_id) end),
          users_discord: Task.async(fn -> Accounts.count_users_with_provider(:discord_id) end),
          users_apple: Task.async(fn -> Accounts.count_users_with_provider(:apple_id) end),
          users_steam: Task.async(fn -> Accounts.count_users_with_provider(:steam_id) end),
          users_device: Task.async(fn -> Accounts.count_users_with_provider(:device_id) end),
          users_password: Task.async(fn -> Accounts.count_users_with_password() end),
          lobbies_hostless: Task.async(fn -> Gamend.Lobbies.count_hostless_lobbies() end),
          lobbies_hidden: Task.async(fn -> Gamend.Lobbies.count_hidden_lobbies() end),
          lobbies_locked: Task.async(fn -> Gamend.Lobbies.count_locked_lobbies() end),
          lobbies_passworded: Task.async(fn -> Gamend.Lobbies.count_passworded_lobbies() end),
          leaderboard_records: Task.async(fn -> Gamend.Leaderboards.count_all_records() end),
          groups_count: Task.async(fn -> Groups.count_all_groups() end),
          groups_public: Task.async(fn -> Groups.count_groups_by_type(GroupType.public()) end),
          groups_private: Task.async(fn -> Groups.count_groups_by_type(GroupType.private()) end),
          groups_hidden: Task.async(fn -> Groups.count_groups_by_type(GroupType.hidden()) end),
          groups_members: Task.async(fn -> Groups.count_all_members() end),
          parties_count: Task.async(fn -> Parties.count_all_parties() end),
          blacklist_count: Task.async(fn -> Gamend.Friends.count_all_blocks() end),
          friends_count: Task.async(fn -> Gamend.Friends.count_all_friendships() end),
          parties_members: Task.async(fn -> Parties.count_all_party_members() end),
          chat_count: Task.async(fn -> Gamend.Chat.count_all_messages() end),
          chat_senders: Task.async(fn -> Gamend.Chat.count_unique_senders() end),
          chat_by_type: Task.async(fn -> Gamend.Chat.count_messages_by_type() end),
          open_reports: Task.async(fn -> Reports.count_open_reports() end),
          report_counts: Task.async(fn -> Gamend.Reports.count_by_status() end),
          host: Task.async(fn -> GamendWeb.AdminCard.load() end),
          active_mutes: Task.async(fn -> Gamend.Chat.count_mutes(%{"active" => true}) end),
          quest_stats: Task.async(fn -> Gamend.Quests.dashboard_stats() end),
          payments_stats: Task.async(fn -> Payments.admin_stats() end),
          translation_stats: Task.async(fn -> TranslationStats.all_completeness() end),
          users_unactivated: Task.async(fn -> Accounts.count_unactivated_users() end),
          oban_stats: Task.async(fn -> safe_oban_stats() end),
          economy_stats: Task.async(fn -> safe_economy_stats() end),
          analytics_stats: Task.async(fn -> safe_analytics_stats() end)
        }

        # Await all tasks (the DB pool handles concurrency)
        Map.new(tasks, fn {key, task} -> {key, Task.await(task, 30_000)} end)
      end)

    # In-memory stats (ETS / GenServer — instant, no DB)
    conn_stats = ConnectionTracker.cluster_counts()
    sys_stats = ConnectionTracker.system_stats()
    rate_stats = build_rate_limit_stats()
    geo = GeoCountry.dashboard_stats()
    log_level_counts = safe_log_count_by_level()
    log_total_buffered = Enum.reduce(log_level_counts, 0, fn {_, v}, acc -> acc + v end)
    log_recent_errors = safe_log_recent_errors()

    if connected?(socket), do: schedule_live_refresh()

    {:ok,
     assign(socket,
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
       host_cards: r.host.cards,
       host_links: r.host.links,
       active_mutes: r.active_mutes,
       translation_stats: r.translation_stats,
       quest_stats: r.quest_stats,
       payments_stats: r.payments_stats,
       conn_stats: conn_stats,
       sys_stats: sys_stats,
       rate_stats: rate_stats,
       ip_ban_count: length(BanCache.list(:ip)),
       account_ban_count: length(BanCache.list(:account)),
       geo_stats: geo.stats_all,
       geo_total: geo.total_all,
       geo_total_1h: geo.total_1h,
       geo_stats_1h: geo.stats_1h,
       geo_crawlers_1h: geo.crawlers_1h,
       geoip_available?: GeoCountry.geoip_available?(),
       log_level_counts: log_level_counts,
       log_total_buffered: log_total_buffered,
       log_recent_errors: log_recent_errors,
       result_counts: safe_result_counts(),
       analytics_stats: r.analytics_stats,
       users_unactivated: r.users_unactivated,
       oban_stats: r.oban_stats,
       economy_stats: r.economy_stats,
       storage_info: safe_storage_info(),
       cache_stats: Gamend.Cache.Stats.snapshot(),
       dev_routes?: @dev_routes?
     )}
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
     )}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp schedule_live_refresh, do: Process.send_after(self(), :refresh_live_stats, 5_000)

  # Core's pages by section, then a host's own (`GamendWeb.AdminCard`).
  defp menu_sections(host_links) do
    Pages.sections() ++ [%{title: "More", links: host_links}]
  end

  # What each tile shows beside its name. A page with no figure worth a glance
  # (Settings, System) is not here.
  defp menu_counts(assigns) do
    %{
      "/admin/users" => assigns.users_count,
      "/admin/sessions" => assigns.sessions_count,
      "/admin/groups" => assigns.groups_count,
      "/admin/parties" => assigns.parties_count,
      "/admin/friends" => assigns.friends_count,
      "/admin/blacklist" => assigns.blacklist_count,
      "/admin/lobbies" => assigns.lobbies_count,
      "/admin/leaderboards" => assigns.leaderboards_count,
      "/admin/tournaments" => assigns.tournaments_count,
      "/admin/matchmaking" => assigns.matchmaking_stats.queued,
      "/admin/quests" => assigns.quest_stats.definitions,
      "/admin/results" => "#{assigns.result_counts.open} open",
      "/admin/chat" => assigns.chat_count,
      "/admin/chat/reports" => assigns.open_reports,
      "/admin/reports" => assigns.content_reports,
      "/admin/bans" => assigns.account_ban_count + assigns.ip_ban_count,
      "/admin/notifications" => assigns.notifications_count,
      "/admin/push" => assigns.push_stats.live,
      "/admin/economy" => assigns.economy_stats.wallets,
      "/admin/payments" => assigns.payments_stats.purchases,
      "/admin/analytics" => "DAU #{assigns.analytics_stats.dau}",
      "/admin/geo" => "#{format_number(assigns.geo_total_1h)}/1h",
      "/admin/kv" => assigns.kv_count,
      "/admin/storage" => assigns.storage_info.adapter,
      "/admin/connections" => assigns.conn_stats.total_connections,
      "/admin/rate_limiting" => assigns.rate_stats.limited,
      "/admin/logs" =>
        ngettext("%{count} error", "%{count} errors", assigns.log_recent_errors) <> "/1h",
      "/admin/oban" => assigns.oban_stats.total
    }
  end

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

  defp cache_hit_rate_label(%{cache: []}), do: "—"

  defp cache_hit_rate_label(%{cache: rows}) do
    hits = Enum.sum_by(rows, & &1.hits)
    total = hits + Enum.sum_by(rows, & &1.misses)

    if total > 0, do: "#{round(hits / total * 100)}%", else: "—"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)

  defp countries_label(n), do: ngettext("%{count} country", "%{count} countries", n)

  defp safe_log_count_by_level do
    GamendWeb.AdminLogBuffer.count_by_level()
  rescue
    _ -> %{}
  end

  defp state_count(counts, state), do: Map.get(counts, state, 0)

  defp entries_total(counts), do: counts |> Map.values() |> Enum.sum()

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
    _ ->
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

  defp pct(nil), do: "—"
  defp pct(rate) when is_float(rate), do: "#{Float.round(rate * 100, 1)}%"

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
    _ -> %{total: 0, executing: 0, available: 0, scheduled: 0, retryable: 0}
  end

  defp safe_result_counts do
    %{total: Gamend.Results.count(), open: Gamend.Results.count(%{status: ResultStatus.open()})}
  rescue
    _ -> %{total: 0, open: 0}
  end
end
