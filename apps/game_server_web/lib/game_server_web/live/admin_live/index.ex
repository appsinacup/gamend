defmodule GameServerWeb.AdminLive.Index do
  use GameServerWeb, :live_view

  alias GameServer.Accounts
  alias GameServer.Accounts.User
  alias GameServer.Accounts.UserToken
  alias GameServer.Groups
  alias GameServer.KV
  alias GameServer.Leaderboards.Leaderboard
  alias GameServer.Lobbies.Lobby
  alias GameServer.Notifications
  alias GameServer.Parties
  alias GameServer.Payments
  alias GameServer.Repo
  alias GameServerWeb.ConnectionTracker
  alias GameServerWeb.Gettext.Stats, as: TranslationStats
  alias GameServerWeb.Plugs.GeoCountry

  @dev_routes? Application.compile_env(:game_server_web, :dev_routes, false)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <div>
          <h1 class="text-3xl font-bold">Admin Dashboard</h1>
          <p class="mt-1 text-sm text-base-content/70">System administration</p>
        </div>

        <div class="flex gap-4 flex-wrap">
          <.link navigate={~p"/admin/config"} class="btn btn-outline">
            Configuration
          </.link>
          <.link navigate={~p"/admin/settings"} class="btn btn-outline">
            Settings
          </.link>
          <.link navigate={~p"/admin/kv"} class="btn btn-outline">
            KV ({@kv_count})
          </.link>
          <.link navigate={~p"/admin/users"} class="btn btn-outline">
            Users ({@users_count})
          </.link>
          <.link navigate={~p"/admin/lobbies"} class="btn btn-outline">
            Lobbies ({@lobbies_count})
          </.link>
          <.link navigate={~p"/admin/leaderboards"} class="btn btn-outline">
            Leaderboards ({@leaderboards_count})
          </.link>
          <.link navigate={~p"/admin/tournaments"} class="btn btn-outline">
            Tournaments ({@tournaments_count})
          </.link>
          <.link navigate={~p"/admin/matchmaking"} class="btn btn-outline">
            Matchmaking ({@matchmaking_stats.queued})
          </.link>
          <.link navigate={~p"/admin/sessions"} class="btn btn-outline">
            Tokens ({@sessions_count})
          </.link>
          <.link navigate={~p"/admin/notifications"} class="btn btn-outline">
            Notifications ({@notifications_count})
          </.link>
          <.link navigate={~p"/admin/push"} class="btn btn-outline">
            Push Devices ({@push_stats.live})
          </.link>
          <.link navigate={~p"/admin/groups"} class="btn btn-outline">
            Groups ({@groups_count})
          </.link>
          <.link navigate={~p"/admin/blacklist"} class="btn btn-outline">
            Blacklist ({@blacklist_count})
          </.link>
          <.link navigate={~p"/admin/parties"} class="btn btn-outline">
            Parties ({@parties_count})
          </.link>
          <.link navigate={~p"/admin/chat"} class="btn btn-outline">
            Chat ({@chat_count})
          </.link>
          <.link navigate={~p"/admin/quests"} class="btn btn-outline">
            Quests ({@quest_stats.definitions})
          </.link>
          <.link navigate={~p"/admin/payments"} class="btn btn-outline">
            Payments ({@payments_stats.purchases})
          </.link>
          <.link navigate={~p"/admin/connections"} class="btn btn-outline">
            Connections ({@conn_stats.total_connections})
          </.link>
          <.link navigate={~p"/admin/rate_limiting"} class="btn btn-outline">
            Rate Limiting ({@rate_stats.limited})
          </.link>
          <.link navigate={~p"/admin/logs"} class="btn btn-outline">
            Logs ({@log_recent_errors} errors/1h)
          </.link>
          <.link navigate={~p"/admin/lobby_snapshots"} class="btn btn-outline">
            Lobby Snapshots ({@lobby_snapshot_runs.total})
          </.link>
          <.link navigate={~p"/admin/geo"} class="btn btn-outline">
            Geo Traffic ({format_number(@geo_total_1h)}/1h)
          </.link>
          <.link navigate={~p"/admin/system"} class="btn btn-outline">
            System
          </.link>
          <.link navigate={~p"/admin/runtime"} class="btn btn-outline">
            Runtime
          </.link>
          <.link href={~p"/admin/oban"} class="btn btn-outline">
            Jobs ({@oban_stats.total})
          </.link>
          <.link navigate={~p"/admin/storage"} class="btn btn-outline">
            Storage ({@storage_info.adapter})
          </.link>
          <.link navigate={~p"/admin/economy"} class="btn btn-outline">
            Economy ({@economy_stats.wallets})
          </.link>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Overview</h2>
            <p>
              Welcome to the admin dashboard. Use the buttons above to navigate to different sections.
            </p>

            <div class="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4">
              <%!-- 1. Users --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Users</div>
                  <.link navigate={~p"/admin/users"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@users_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>With email: {@users_password}</div>
                  <div>Google: {@users_google}</div>
                  <div>Facebook: {@users_facebook}</div>
                  <div>Discord: {@users_discord}</div>
                  <div>Apple: {@users_apple}</div>
                  <div>Steam: {@users_steam}</div>
                  <div>Device-linked: {@users_device}</div>
                </div>
              </div>

              <%!-- 2. Registration --%>
              <div class="card bg-base-100 p-4">
                <div class="text-sm font-semibold mb-2">Registration</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div class="font-semibold">Last 24 hours: {@users_registered_1d}</div>
                  <div class="font-semibold mt-2">
                    Last 7 days: {@users_registered_7d}
                  </div>
                  <div class="font-semibold mt-2">
                    Last 30 days: {@users_registered_30d}
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
                </div>
              </div>

              <%!-- 3. Activity --%>
              <div class="card bg-base-100 p-4">
                <div class="text-sm font-semibold mb-2">Activity</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div class="font-semibold">Last 24 hours: {@users_active_1d}</div>
                  <div class="font-semibold mt-2">Last 7 days: {@users_active_7d}</div>
                  <div class="font-semibold mt-2">Last 30 days: {@users_active_30d}</div>
                </div>
              </div>

              <%!-- 4. Lobbies --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Lobbies</div>
                  <.link navigate={~p"/admin/lobbies"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@lobbies_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Hostless: {@lobbies_hostless}</div>
                  <div>Hidden: {@lobbies_hidden}</div>
                  <div>Locked: {@lobbies_locked}</div>
                  <div>With password: {@lobbies_passworded}</div>
                </div>
              </div>

              <%!-- 5. Leaderboards --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Leaderboards</div>
                  <.link navigate={~p"/admin/leaderboards"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@leaderboards_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Scores total: {@leaderboard_records}</div>
                </div>
              </div>

              <%!-- Tournaments --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Tournaments</div>
                  <.link navigate={~p"/admin/tournaments"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@tournaments_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
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
                    Past deadline_at: {@tournament_stats.matches.overdue}
                  </div>
                </div>
              </div>

              <%!-- Matchmaking --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Matchmaking</div>
                  <.link navigate={~p"/admin/matchmaking"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@matchmaking_stats.queued}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
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
                </div>
              </div>

              <%!-- 6. Groups --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Groups</div>
                  <.link navigate={~p"/admin/groups"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@groups_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Public: {@groups_public}</div>
                  <div>Private: {@groups_private}</div>
                  <div>Hidden: {@groups_hidden}</div>
                  <div>Total members: {@groups_members}</div>
                </div>
              </div>

              <%!-- 7. Parties --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Parties</div>
                  <.link navigate={~p"/admin/parties"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@parties_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Total members: {@parties_members}</div>
                </div>
              </div>

              <%!-- 8. Chat --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Chat</div>
                  <.link navigate={~p"/admin/chat"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@chat_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Users who wrote: {@chat_senders}</div>
                  <div>Users who never wrote: {@chat_silent}</div>
                  <div>In lobbies: {@chat_by_lobby}</div>
                  <div>In groups: {@chat_by_group}</div>
                  <div>Friend DMs: {@chat_by_friend}</div>
                </div>
              </div>

              <%!-- 9. Translations --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Translations</div>
                  <.link navigate={~p"/admin/translations"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">
                  {length(@translation_stats)} languages
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
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
                    <span class="font-mono text-[0.65rem] w-10 text-right">{stats.percent}%</span>
                  </div>
                </div>
              </div>

              <%!-- 10. Key-Value --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Key-Value</div>
                  <.link navigate={~p"/admin/kv"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@kv_count}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Global entries: {@kv_global}</div>
                  <div>User entries: {@kv_user}</div>
                </div>
              </div>

              <%!-- 11a. Quests --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Quests</div>
                  <.link navigate={~p"/admin/quests"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@quest_stats.definitions}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Active: {@quest_stats.active_definitions}</div>
                  <div>Completions today: {@quest_stats.completions_today}</div>
                  <div>Claims today: {@quest_stats.claims_today}</div>
                  <div>Claimable now: {@quest_stats.claimable_now}</div>
                </div>
              </div>

              <%!-- 12. Live Connections --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Connections</div>
                  <.link
                    navigate={~p"/admin/connections"}
                    class="text-xs text-primary hover:underline"
                  >
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@conn_stats.total_connections}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>WS sockets: {@conn_stats.ws_sockets}</div>
                  <div>WS channels: {@conn_stats.total_channels}</div>
                  <div>LiveViews: {@conn_stats.live_views}</div>
                  <div>WebRTC: {@conn_stats.webrtc_peers}</div>
                </div>
              </div>

              <%!-- 13. System (BEAM) --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">System</div>
                  <.link navigate={~p"/admin/system"} class="text-xs text-primary hover:underline">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">
                  {GameServerWeb.ConnectionTracker.format_uptime(@sys_stats.uptime_seconds)}
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>OTP: {@sys_stats.otp_release}</div>
                  <div>Schedulers: {@sys_stats.schedulers}</div>
                  <div>Node: {@sys_stats.node}</div>
                  <div>Cluster: {@sys_stats.cluster_size} nodes</div>
                  <div>Memory: {@sys_stats.memory_total_mb} MB</div>
                  <div>
                    Processes: {@sys_stats.process_count} / {format_number(@sys_stats.process_limit)}
                  </div>
                </div>
              </div>

              <%!-- 14. Rate Limiting --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Rate Limiting</div>
                  <.link navigate={~p"/admin/rate_limiting"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-2">
                  <div class="flex justify-between items-center">
                    <span>IP Banned (1h)</span>
                    <span class={[
                      "badge badge-sm font-mono",
                      if(@rate_stats.banned > 0, do: "badge-error", else: "badge-ghost opacity-50")
                    ]}>
                      {@rate_stats.banned}
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
                </div>
              </div>

              <%!-- 15. Geo Traffic --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Geo Traffic</div>
                  <.link navigate={~p"/admin/geo"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold font-mono">{format_number(@geo_total)}</div>
                <div class="text-xs text-base-content/60 mt-1">
                  {length(@geo_stats)} countries &middot; {if(@geoip_available?,
                    do: "MMDB",
                    else: "CF header"
                  )}
                </div>
                <div class="text-xs text-base-content/60 mt-2 flex justify-between items-center">
                  <span>Last hour</span>
                  <span class="font-mono font-semibold">
                    {format_number(@geo_total_1h)} reqs &middot; {length(@geo_stats_1h)} countries
                  </span>
                </div>
                <div :if={@geo_stats_1h != []} class="text-xs text-base-content/60 mt-1 space-y-1">
                  <%= for {country, count} <- Enum.take(@geo_stats_1h, 3) do %>
                    <div class="flex justify-between items-center">
                      <span class="font-mono">{country_flag(country)} {country}</span>
                      <span class="font-mono">{format_number(count)} (1h)</span>
                    </div>
                  <% end %>
                  <div :if={length(@geo_stats_1h) > 3} class="text-center opacity-50">
                    +{length(@geo_stats_1h) - 3} more
                  </div>
                </div>
              </div>

              <%!-- 16. Lobby snapshots --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Lobby snapshots</div>
                  <.link navigate={~p"/admin/lobby_snapshots"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">
                  {@lobby_snapshot_runs.total}
                  <span class="text-sm font-normal text-base-content/60 ml-1">recent runs</span>
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div class="flex justify-between">
                    <span>Flagged</span>
                    <span class={["font-mono", @lobby_snapshot_runs.flagged > 0 && "text-error"]}>
                      {@lobby_snapshot_runs.flagged}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- 17. Logs --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Logs</div>
                  <.link navigate={~p"/admin/logs"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">
                  <span :if={@log_recent_errors > 0} class="text-error">{@log_recent_errors}</span>
                  <span :if={@log_recent_errors == 0} class="text-success">0</span>
                  <span class="text-sm font-normal text-base-content/60 ml-1">errors (1h)</span>
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
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
                </div>
              </div>

              <%!-- 18. Background jobs --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Background jobs</div>
                  <.link href={~p"/admin/oban"} class="link link-primary text-xs">
                    Dashboard →
                  </.link>
                </div>
                <div class="text-2xl font-bold">
                  {@oban_stats.total}
                  <span class="text-sm font-normal text-base-content/60 ml-1">jobs</span>
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
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
                </div>
              </div>

              <%!-- 19. Storage --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Storage</div>
                  <.link navigate={~p"/admin/storage"} class="link link-primary text-xs">
                    Manage →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@storage_info.adapter}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div class="flex justify-between">
                    <span>Target</span>
                    <span class="font-mono truncate ml-2">{@storage_info.detail}</span>
                  </div>
                </div>
              </div>

              <%!-- 20. Economy --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Economy</div>
                  <.link navigate={~p"/admin/economy"} class="link link-primary text-xs">
                    Manage →
                  </.link>
                </div>
                <div class="text-2xl font-bold">
                  {@economy_stats.wallets}
                  <span class="text-sm font-normal text-base-content/60 ml-1">wallets</span>
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div class="flex justify-between">
                    <span>Ledger entries</span>
                    <span class="font-mono">{@economy_stats.ledger}</span>
                  </div>
                </div>
              </div>

              <%!-- 12. Payments --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Payments</div>
                  <.link navigate={~p"/admin/payments"} class="link link-primary text-xs">
                    View →
                  </.link>
                </div>
                <div class="text-2xl font-bold">{@payments_stats.purchases}</div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
                  <div>Completed: {@payments_stats.completed_purchases}</div>
                  <div>Products: {@payments_stats.products}</div>
                  <div>Provider SKUs: {@payments_stats.provider_products}</div>
                  <div>Active entitlements: {@payments_stats.active_entitlements}</div>
                </div>
              </div>

              <%!-- 13. Cache & limits (since boot) --%>
              <div class="card bg-base-100 p-4">
                <div class="flex items-center justify-between mb-2">
                  <div class="text-sm font-semibold">Cache &amp; limits</div>
                  <span class="text-xs text-base-content/50">since boot</span>
                </div>
                <div class="text-2xl font-bold">
                  {cache_hit_rate_label(@cache_stats)}
                  <span class="text-sm font-normal text-base-content/60 ml-1">hit rate</span>
                </div>
                <div class="text-xs text-base-content/60 mt-2 space-y-1">
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
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # Fire all independent DB queries in parallel for fast mount
    tasks = %{
      users_count: Task.async(fn -> Repo.aggregate(User, :count) end),
      sessions_count: Task.async(fn -> Repo.aggregate(UserToken, :count) end),
      lobbies_count: Task.async(fn -> Repo.aggregate(Lobby, :count) end),
      notifications_count: Task.async(fn -> Notifications.count_all_notifications() end),
      push_stats: Task.async(fn -> GameServer.Push.token_stats() end),
      leaderboards_count: Task.async(fn -> Repo.aggregate(Leaderboard, :count) end),
      tournaments_count:
        Task.async(fn -> Repo.aggregate(GameServer.Tournaments.Tournament, :count) end),
      tournament_stats: Task.async(fn -> GameServer.Tournaments.stats() end),
      matchmaking_stats: Task.async(fn -> GameServer.Matchmaking.stats() end),
      ready_check_stats: Task.async(fn -> GameServer.ReadyChecks.stats() end),
      kv_count: Task.async(fn -> KV.count_entries() end),
      kv_global: Task.async(fn -> KV.count_entries(global_only: true) end),
      users_google: Task.async(fn -> Accounts.count_users_with_provider(:google_id) end),
      users_facebook: Task.async(fn -> Accounts.count_users_with_provider(:facebook_id) end),
      users_discord: Task.async(fn -> Accounts.count_users_with_provider(:discord_id) end),
      users_apple: Task.async(fn -> Accounts.count_users_with_provider(:apple_id) end),
      users_steam: Task.async(fn -> Accounts.count_users_with_provider(:steam_id) end),
      users_device: Task.async(fn -> Accounts.count_users_with_provider(:device_id) end),
      users_password: Task.async(fn -> Accounts.count_users_with_password() end),
      lobbies_hostless: Task.async(fn -> GameServer.Lobbies.count_hostless_lobbies() end),
      lobbies_hidden: Task.async(fn -> GameServer.Lobbies.count_hidden_lobbies() end),
      lobbies_locked: Task.async(fn -> GameServer.Lobbies.count_locked_lobbies() end),
      lobbies_passworded: Task.async(fn -> GameServer.Lobbies.count_passworded_lobbies() end),
      leaderboard_records: Task.async(fn -> GameServer.Leaderboards.count_all_records() end),
      groups_count: Task.async(fn -> Groups.count_all_groups() end),
      groups_public: Task.async(fn -> Groups.count_groups_by_type("public") end),
      groups_private: Task.async(fn -> Groups.count_groups_by_type("private") end),
      groups_hidden: Task.async(fn -> Groups.count_groups_by_type("hidden") end),
      groups_members: Task.async(fn -> Groups.count_all_members() end),
      parties_count: Task.async(fn -> Parties.count_all_parties() end),
      blacklist_count: Task.async(fn -> GameServer.Friends.count_all_blocks() end),
      parties_members: Task.async(fn -> Parties.count_all_party_members() end),
      chat_count: Task.async(fn -> GameServer.Chat.count_all_messages() end),
      chat_senders: Task.async(fn -> GameServer.Chat.count_unique_senders() end),
      chat_by_type: Task.async(fn -> GameServer.Chat.count_messages_by_type() end),
      quest_stats: Task.async(fn -> GameServer.Quests.dashboard_stats() end),
      payments_stats: Task.async(fn -> Payments.admin_stats() end),
      translation_stats: Task.async(fn -> TranslationStats.all_completeness() end),
      users_registered_1d: Task.async(fn -> Accounts.count_users_registered_since(1) end),
      users_registered_7d: Task.async(fn -> Accounts.count_users_registered_since(7) end),
      users_registered_30d: Task.async(fn -> Accounts.count_users_registered_since(30) end),
      users_active_1d: Task.async(fn -> Accounts.count_users_active_since(1) end),
      users_active_7d: Task.async(fn -> Accounts.count_users_active_since(7) end),
      users_active_30d: Task.async(fn -> Accounts.count_users_active_since(30) end),
      users_unactivated: Task.async(fn -> Accounts.count_unactivated_users() end),
      oban_stats: Task.async(fn -> safe_oban_stats() end),
      economy_stats: Task.async(fn -> safe_economy_stats() end)
    }

    # Await all tasks (the DB pool handles concurrency)
    r = Map.new(tasks, fn {key, task} -> {key, Task.await(task, 10_000)} end)

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
       users_count: r.users_count,
       sessions_count: r.sessions_count,
       lobbies_count: r.lobbies_count,
       leaderboards_count: r.leaderboards_count,
       tournaments_count: r.tournaments_count,
       matchmaking_stats: r.matchmaking_stats,
       ready_check_stats: r.ready_check_stats,
       tournament_stats: r.tournament_stats,
       kv_count: r.kv_count,
       kv_global: r.kv_global,
       kv_user: r.kv_count - r.kv_global,
       users_google: r.users_google,
       users_facebook: r.users_facebook,
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
       parties_members: r.parties_members,
       chat_count: r.chat_count,
       chat_senders: r.chat_senders,
       chat_silent: max(r.users_count - r.chat_senders, 0),
       chat_by_lobby: Map.get(r.chat_by_type, "lobby", 0),
       chat_by_group: Map.get(r.chat_by_type, "group", 0),
       chat_by_friend: Map.get(r.chat_by_type, "friend", 0),
       translation_stats: r.translation_stats,
       quest_stats: r.quest_stats,
       payments_stats: r.payments_stats,
       conn_stats: conn_stats,
       sys_stats: sys_stats,
       rate_stats: rate_stats,
       geo_stats: geo.stats_all,
       geo_total: geo.total_all,
       geo_total_1h: geo.total_1h,
       geo_stats_1h: geo.stats_1h,
       geoip_available?: GeoCountry.geoip_available?(),
       log_level_counts: log_level_counts,
       log_total_buffered: log_total_buffered,
       log_recent_errors: log_recent_errors,
       lobby_snapshot_runs: safe_lobby_snapshot_runs(),
       users_registered_1d: r.users_registered_1d,
       users_registered_7d: r.users_registered_7d,
       users_registered_30d: r.users_registered_30d,
       users_active_1d: r.users_active_1d,
       users_active_7d: r.users_active_7d,
       users_active_30d: r.users_active_30d,
       users_unactivated: r.users_unactivated,
       oban_stats: r.oban_stats,
       economy_stats: r.economy_stats,
       storage_info: safe_storage_info(),
       cache_stats: GameServer.Cache.Stats.snapshot(),
       dev_routes?: @dev_routes?
     )}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
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
       geo_stats: geo.stats_all,
       geo_total: geo.total_all,
       geo_total_1h: geo.total_1h,
       geo_stats_1h: geo.stats_1h,
       log_recent_errors: safe_log_recent_errors(),
       cache_stats: GameServer.Cache.Stats.snapshot()
     )}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp schedule_live_refresh, do: Process.send_after(self(), :refresh_live_stats, 5_000)

  defp build_rate_limit_stats do
    # Counter inspection only works for the ETS backend; with the Redis
    # backend the "Cache & limits" card (deny telemetry) covers this.
    case GameServerWeb.RateLimit.backend() do
      GameServerWeb.RateLimit.ETS -> build_rate_limit_stats(GameServerWeb.RateLimit.ETS)
      _other -> %{banned: 0, limited: 0}
    end
  end

  defp build_rate_limit_stats(table) do
    :ets.tab2list(table)
    |> Enum.reduce(%{banned: 0, limited: 0}, fn
      {{key, _window}, count, _expiry}, acc when is_binary(key) ->
        cond do
          String.starts_with?(key, "ip_ban:") ->
            %{acc | banned: acc.banned + 1}

          String.starts_with?(key, "auth:") or String.starts_with?(key, "general:") ->
            limit = if String.starts_with?(key, "auth:"), do: 10, else: 120
            limited_inc = if count >= limit, do: 1, else: 0
            %{acc | limited: acc.limited + limited_inc}

          true ->
            acc
        end

      _, acc ->
        acc
    end)
  rescue
    _ -> %{banned: 0, limited: 0}
  end

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

  # Convert ISO 3166-1 alpha-2 country code to its flag emoji.
  # Works by offseting each letter into the Regional Indicator Symbol range.
  defp country_flag(code) when is_binary(code) and byte_size(code) == 2 do
    code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(fn c -> c - ?A + 0x1F1E6 end)
    |> List.to_string()
  rescue
    _ -> "🌐"
  end

  defp country_flag(_), do: "🌐"

  defp safe_log_count_by_level do
    GameServerWeb.AdminLogBuffer.count_by_level()
  rescue
    _ -> %{}
  end

  defp state_count(counts, state), do: Map.get(counts, state, 0)

  defp entries_total(counts), do: counts |> Map.values() |> Enum.sum()

  defp safe_log_recent_errors do
    GameServerWeb.AdminLogBuffer.count_recent_errors(3600)
  rescue
    _ -> 0
  end

  defp safe_economy_stats do
    %{wallets: GameServer.Economy.count_wallets(), ledger: GameServer.Economy.count_ledger()}
  rescue
    _ -> %{wallets: 0, ledger: 0}
  end

  defp safe_storage_info do
    case GameServer.Storage.adapter() do
      GameServer.Storage.S3 ->
        cfg = Application.get_env(:game_server_core, GameServer.Storage.S3, [])
        %{adapter: "S3", detail: cfg[:bucket] || "—"}

      _ ->
        cfg = Application.get_env(:game_server_core, GameServer.Storage.Local, [])
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

  defp safe_lobby_snapshot_runs do
    %{
      total: length(GameServer.LobbySnapshots.list_lobbies(limit: 50)),
      flagged: length(GameServer.LobbySnapshots.list_lobbies(limit: 50, flagged_only: true))
    }
  rescue
    _ -> %{total: 0, flagged: 0}
  end
end
