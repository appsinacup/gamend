defmodule GamendWeb.AdminLive.IndexCards do
  @moduledoc """
  The cards of `/admin` (`GamendWeb.AdminLive.Index`), section by section, as
  data: each card names its page, whose title, icon and colour come from
  `GamendWeb.AdminLive.Pages`, and says its figure and the lines under it,
  from the dashboard's assigns. They were 450 lines of hand-written template.

  A line (`line/1`) is one of:

    * `"text"`
    * `{label, value}`: `label: value`
    * `{label, value, path}`: the value a link to `path`; `nil`, the label is
    * `{:class, class, text}`: a line in a tone of its own
    * `{:row, label, value, opts}`: the label left, the value right;
      `opts` are `value_class` (`"font-mono"` by default), `label_class`,
      `class` (the row's) and `center`
    * `{:badge, label, value, class}`: the value as a badge
    * `{:bar, locale, percent}`: a language's translation, as a bar
    * `{:alert_link, text, path}`: a warning under a rule, linking to `path`

  A host's cards (`GamendWeb.AdminCard`) use the first three.
  """

  use GamendWeb, :html

  alias GamendWeb.AdminLive.Shared

  require Gamend.Tournaments.EntryState, as: EntryState
  require Gamend.Tournaments.TournamentState, as: TournamentState

  @translations_shown 3

  @doc "The sections and their cards, in order, from the dashboard's assigns."
  @spec sections(map()) :: [{String.t(), [map()]}]
  def sections(a) do
    [
      {"Players", [users(a), registration(a), sessions(a), activity(a)]},
      {"Gameplay",
       [
         lobbies(a),
         matchmaking(a),
         tournaments(a),
         leaderboards(a),
         quests(a),
         results(a),
         economy(a),
         payments(a)
       ]},
      {"Social",
       [
         groups(a),
         parties(a),
         friends(a),
         blacklist(a),
         chat(a),
         notifications(a),
         push(a)
       ]},
      {"Moderation", [chat_reports(a), chat_filter(), reports(a), bans(a)]},
      {"Data", [translations(a), kv(a), storage(a), retention()]},
      {"Configuration", [plugins(a), theme(), settings(), limits(), rate_limiting(a)]},
      {"Server",
       [
         cache(a),
         system(a),
         runtime(),
         connections(a),
         dashboard(),
         logs(a),
         oban(a),
         geo(a),
         github(a)
       ]}
    ]
  end

  # ── Players ─────────────────────────────────────────────────────────────

  defp users(a) do
    %{
      id: :users,
      page: "/admin/users",
      value: a.users_count,
      lines: [
        {"With password", a.users_password},
        {"Google", a.users_google},
        {"Facebook", a.users_facebook},
        {"GitHub", a.users_github},
        {"Discord", a.users_discord},
        {"Apple", a.users_apple},
        {"Steam", a.users_steam},
        {"Device-linked", a.users_device}
      ]
    }
  end

  defp registration(a) do
    activity = a.snapshot.activity

    %{
      id: :registration,
      page: "/admin/users",
      title: "Registration",
      icon: "hero-user-plus-solid",
      color: "emerald",
      lines:
        [
          {:class, "font-semibold", "Today: #{activity.new_users_1d}"},
          {:class, "font-semibold mt-2", "Last 7 days: #{activity.new_users_7d}"},
          {:class, "font-semibold mt-2", "Last 30 days: #{activity.new_users_30d}"}
        ] ++
          if(a.users_unactivated > 0,
            do: [
              {:alert_link, "Pending activation: #{a.users_unactivated}",
               ~p"/admin/users?filter=unactivated"}
            ],
            else: []
          )
    }
  end

  defp sessions(a) do
    %{
      id: :sessions,
      page: "/admin/sessions",
      value: a.sessions_count,
      lines: ["Signed-in browser sessions"]
    }
  end

  defp activity(a) do
    %{snapshot: %{activity: activity}, analytics_stats: stats} = a

    %{
      id: :activity,
      page: "/admin/analytics",
      title: "Activity",
      icon: "hero-bolt-solid",
      lines: [
        {:class, "font-semibold", "Today (DAU): #{activity.dau}"},
        {:class, "font-semibold mt-2", "Last 7 days (WAU): #{activity.wau}"},
        {:class, "font-semibold mt-2", "Last 30 days (MAU): #{activity.mau}"},
        {:class, "mt-3 pt-2 border-t border-base-300", "Stickiness: #{pct(stats.stickiness)}"},
        {"D1 / D7 / D30", "#{pct(stats.d1)} / #{pct(stats.d7)} / #{pct(stats.d30)}"},
        {"Payer conversion (30d)", pct(stats.conversion_30d)}
      ]
    }
  end

  # ── Gameplay ────────────────────────────────────────────────────────────

  defp lobbies(a) do
    %{
      id: :lobbies,
      page: "/admin/lobbies",
      value: a.lobbies_count,
      lines: [
        {"Hostless", a.lobbies_hostless},
        {"Hidden", a.lobbies_hidden},
        {"Locked", a.lobbies_locked},
        {"With password", a.lobbies_passworded}
      ]
    }
  end

  defp matchmaking(a) do
    %{matchmaking_stats: stats, ready_check_stats: checks} = a

    %{
      id: :matchmaking,
      page: "/admin/matchmaking",
      value: stats.queued,
      lines: [
        {"In queue now", stats.queued},
        "Matched: #{stats.matched} · Cancelled: #{stats.cancelled}",
        {"Active queues", length(stats.queues)},
        "Ready checks 24h: #{Map.get(checks, "passed", 0)} passed · " <>
          "#{Map.get(checks, "failed", 0)} failed"
      ]
    }
  end

  defp tournaments(a) do
    %{tournaments: states, entries: entries, matches: matches} = a.tournament_stats

    %{
      id: :tournaments,
      page: "/admin/tournaments",
      value: a.tournaments_count,
      lines:
        [
          "Running: #{state_count(states, TournamentState.running())} · " <>
            "Registration: #{state_count(states, TournamentState.registration())}",
          "Scheduled: #{state_count(states, TournamentState.scheduled())} · " <>
            "Finished: #{state_count(states, TournamentState.finished())}",
          {"Participants", entries |> Map.values() |> Enum.sum()},
          "Still in: #{state_count(entries, EntryState.active())} · " <>
            "Eliminated: #{state_count(entries, EntryState.eliminated())}",
          "Champions: #{state_count(entries, EntryState.winner())} · " <>
            "Awaiting draw: #{state_count(entries, EntryState.registered())}",
          "Matches: #{matches.open} open / #{matches.total}"
        ] ++
          if(matches.overdue > 0,
            do: [{:class, "text-warning", "Past deadline: #{matches.overdue}"}],
            else: []
          )
    }
  end

  defp leaderboards(a) do
    %{
      id: :leaderboards,
      page: "/admin/leaderboards",
      value: a.leaderboards_count,
      lines: [{"Scores total", a.leaderboard_records}]
    }
  end

  defp quests(a) do
    stats = a.quest_stats

    %{
      id: :quests,
      page: "/admin/quests",
      value: stats.definitions,
      lines: [
        {"Active", stats.active_definitions},
        {"Completions today", stats.completions_today},
        {"Claims today", stats.claims_today},
        {"Claimable now", stats.claimable_now}
      ]
    }
  end

  defp results(a) do
    %{
      id: :results,
      page: "/admin/results",
      value: a.result_counts.total,
      unit: "plays",
      lines: [{:row, "Open", a.result_counts.open, []}]
    }
  end

  defp economy(a) do
    %{
      id: :economy,
      page: "/admin/economy",
      value: a.economy_stats.wallets,
      # literal-ok: the figure's unit, not a table
      unit: "wallets",
      lines: [{:row, "Ledger entries", a.economy_stats.ledger, []}]
    }
  end

  defp payments(a) do
    stats = a.payments_stats

    %{
      id: :payments,
      page: "/admin/payments",
      value: stats.purchases,
      lines: [
        {"Completed", stats.completed_purchases},
        {"Products", stats.products},
        {"Provider SKUs", stats.provider_products},
        {"Active entitlements", stats.active_entitlements}
      ]
    }
  end

  # ── Social ──────────────────────────────────────────────────────────────

  defp groups(a) do
    %{
      id: :groups,
      page: "/admin/groups",
      value: a.groups_count,
      lines: [
        {"Public", a.groups_public},
        {"Private", a.groups_private},
        {"Hidden", a.groups_hidden},
        {"Total members", a.groups_members}
      ]
    }
  end

  defp parties(a) do
    %{
      id: :parties,
      page: "/admin/parties",
      value: a.parties_count,
      lines: [{"Total members", a.parties_members}]
    }
  end

  defp friends(a),
    do: %{id: :friends, page: "/admin/friends", value: a.friends_count, lines: ["Friendships"]}

  defp blacklist(a) do
    %{
      id: :blacklist,
      page: "/admin/blacklist",
      value: a.blacklist_count,
      lines: ["Blocks between players"]
    }
  end

  defp chat(a) do
    %{
      id: :chat,
      page: "/admin/chat",
      value: a.chat_count,
      lines: [
        {"Users who wrote", a.chat_senders},
        {"Users who never wrote", a.chat_silent},
        {"In lobbies", a.chat_by_lobby},
        {"In groups", a.chat_by_group},
        {"Friend DMs", a.chat_by_friend}
      ]
    }
  end

  defp notifications(a) do
    %{
      id: :notifications,
      page: "/admin/notifications",
      value: a.notifications_count,
      lines: ["In-app notifications stored"]
    }
  end

  defp push(a) do
    %{
      id: :push,
      page: "/admin/push",
      value: a.push_stats.live,
      lines: [{"Disabled", a.push_stats.disabled} | Enum.to_list(a.push_stats.by_platform)]
    }
  end

  # ── Moderation ──────────────────────────────────────────────────────────

  defp chat_reports(a) do
    %{
      id: :chat_reports,
      page: "/admin/chat/reports",
      title: "Chat moderation",
      value: a.open_reports,
      lines: ["Open reports", {"Active mutes", a.active_mutes, ~p"/admin/bans?kind=chat"}]
    }
  end

  defp chat_filter,
    do: %{
      id: :chat_filter,
      page: "/admin/chat/filter",
      lines: ["Blocked words, and a box to test a phrase"]
    }

  defp reports(a) do
    counts = a.report_counts

    %{
      id: :reports,
      page: "/admin/reports",
      value: a.content_reports,
      lines: [
        "Open reports",
        {"Fixed", Map.get(counts, "fixed", 0)},
        {"Won't fix", Map.get(counts, "wontfix", 0)},
        {"Duplicate", Map.get(counts, "duplicate", 0)}
      ]
    }
  end

  defp bans(a) do
    %{
      id: :bans,
      page: "/admin/bans",
      lines: [
        {:badge, "Banned accounts", a.account_ban_count,
         tone(a.account_ban_count, "badge-error")},
        {:badge, "Banned IPs", a.ip_ban_count, tone(a.ip_ban_count, "badge-error")}
      ]
    }
  end

  # ── Data ────────────────────────────────────────────────────────────────

  defp translations(a) do
    stats = a.translation_stats
    hidden = max(length(stats) - @translations_shown, 0)

    shown =
      stats
      |> Enum.sort_by(& &1.percent)
      |> Enum.take(@translations_shown)
      |> Enum.map(&{:bar, &1.locale, &1.percent})

    %{
      id: :translations,
      page: "/admin/translations",
      value: ngettext("%{count} language", "%{count} languages", length(stats)),
      lines: shown ++ if(hidden > 0, do: ["+#{hidden} more"], else: [])
    }
  end

  defp kv(a) do
    %{
      id: :kv,
      page: "/admin/kv",
      value: a.kv_count,
      lines: [{"Global entries", a.kv_global}, {"User entries", a.kv_user}]
    }
  end

  defp storage(a) do
    %{
      id: :storage,
      page: "/admin/storage",
      value: a.storage_info.adapter,
      lines: [{:row, "Target", a.storage_info.detail, value_class: "font-mono truncate ml-2"}]
    }
  end

  defp retention,
    do: %{
      id: :retention,
      page: "/admin/retention",
      lines: ["What is kept, for how long, and the last sweep"]
    }

  # ── Configuration ───────────────────────────────────────────────────────

  defp plugins(a) do
    lines = ["Reload, build and call"]

    lines =
      if a.plugin_errors > 0,
        do: [
          {:class, "text-error",
           ngettext("%{count} failed to load", "%{count} failed to load", a.plugin_errors)}
          | lines
        ],
        else: lines

    %{id: :plugins, page: "/admin/plugins", value: a.plugin_count, lines: lines}
  end

  defp theme,
    do: %{
      id: :theme,
      page: "/admin/theme",
      lines: ["Branding, navigation and footer as resolved"]
    }

  defp settings,
    do: %{id: :settings, page: "/admin/settings", lines: ["Every setting the server declares"]}

  defp limits do
    %{
      id: :limits,
      page: "/admin/settings",
      path: "/admin/settings?group=limits",
      title: "Limits",
      icon: "hero-scale-solid",
      color: "amber",
      lines: ["Size and count caps, by area"]
    }
  end

  defp rate_limiting(a) do
    limited = a.rate_stats.limited

    %{
      id: :rate_limiting,
      page: "/admin/rate_limiting",
      lines: [{:badge, "Rate Limited (1m)", limited, tone(limited, "badge-warning")}]
    }
  end

  # ── Server ──────────────────────────────────────────────────────────────

  defp cache(a) do
    stats = a.cache_stats

    rows =
      for row <- Enum.take(stats.cache, 6) do
        hits = "#{row.hits}/#{row.hits + row.misses} (#{round(row.hit_rate * 100)}%)"
        {:row, row.prefix, hits, []}
      end

    %{
      id: :cache,
      page: "/admin/system",
      title: "Cache & limits",
      icon: "hero-bolt-solid",
      color: "lime",
      value: cache_hit_rate_label(stats),
      unit: "hit rate since boot",
      lines:
        rows ++
          [
            {:row, "Rate-limit denials", stats.rate_limit_denies |> Map.values() |> Enum.sum(),
             class: "border-t border-base-300 pt-1 mt-1"},
            {:row, "Async overloads", stats.async_overloads,
             value_class: ["font-mono", stats.async_overloads > 0 && "text-warning"]}
          ]
    }
  end

  defp system(a) do
    sys = a.sys_stats

    %{
      id: :system,
      page: "/admin/system",
      value: GamendWeb.ConnectionTracker.format_uptime(sys.uptime_seconds),
      lines: [
        {"OTP", sys.otp_release},
        {"Schedulers", sys.schedulers},
        {"Node", sys.node},
        {"Cluster", ngettext("%{count} node", "%{count} nodes", sys.cluster_size)},
        {"Memory", "#{sys.memory_total_mb} MB"},
        {"Processes", "#{sys.process_count} / #{format_number(sys.process_limit)}"}
      ]
    }
  end

  defp runtime,
    do: %{id: :runtime, page: "/admin/runtime", lines: ["Read-only; reflects the running node"]}

  defp connections(a) do
    conn = a.conn_stats

    %{
      id: :connections,
      page: "/admin/connections",
      value: conn.total_connections,
      lines: [
        {"WS sockets", conn.ws_sockets},
        {"WS channels", conn.total_channels},
        {"LiveViews", conn.live_views},
        {"WebRTC", conn.webrtc_peers}
      ]
    }
  end

  defp dashboard,
    do: %{id: :dashboard, page: "/admin/dashboard", lines: ["Processes, ports, ETS and metrics"]}

  defp logs(a) do
    levels =
      for {level, count} <- a.log_level_counts do
        {:row, level, count,
         value_class: [
           "font-mono",
           level == :error && "text-error",
           level == :warning && "text-warning"
         ]}
      end

    %{
      id: :logs,
      page: "/admin/logs",
      value: a.log_recent_errors,
      unit: "errors (1h)",
      value_class: if(a.log_recent_errors > 0, do: "text-error", else: "text-success"),
      lines: [{:row, "Buffered", a.log_total_buffered, []} | levels]
    }
  end

  defp oban(a) do
    stats = a.oban_stats

    %{
      id: :oban,
      page: "/admin/oban",
      title: "Background jobs",
      value: stats.total,
      # literal-ok: the figure's unit, not a queue
      unit: "jobs",
      lines: [
        {:row, "Executing", stats.executing, []},
        {:row, "Available", stats.available, []},
        {:row, "Scheduled", stats.scheduled, []},
        {:row, "Retryable", stats.retryable,
         value_class: ["font-mono", stats.retryable > 0 && "text-warning"]}
      ]
    }
  end

  defp geo(a) do
    crawler_share =
      if a.geo_total_1h > 0, do: round(a.geo_crawlers_1h / a.geo_total_1h * 100), else: 0

    countries =
      for {country, count} <- Enum.take(a.geo_stats_1h, 3) do
        {:row, "#{Shared.country_flag(country)} #{country}", "#{format_number(count)} (1h)",
         label_class: "font-mono", center: true}
      end

    more =
      if length(a.geo_stats_1h) > 3,
        do: [{:class, "text-center opacity-50", "+#{length(a.geo_stats_1h) - 3} more"}],
        else: []

    %{
      id: :geo,
      page: "/admin/geo",
      value: format_number(a.geo_total),
      lines:
        [
          "#{countries_label(length(a.geo_stats))} · " <>
            if(a.geoip_available?, do: "MMDB", else: "CF header"),
          {:row, "Last hour",
           "#{format_number(a.geo_total_1h)} reqs · #{countries_label(length(a.geo_stats_1h))}",
           value_class: "font-mono font-semibold", center: true},
          {:row, "Crawlers, last hour", "#{format_number(a.geo_crawlers_1h)} · #{crawler_share}%",
           value_class: "font-mono font-semibold", center: true}
        ] ++ countries ++ more
    }
  end

  defp github(a) do
    %{
      id: :github,
      page: "/admin/github",
      value: a.github_installations,
      lines: ["Every installation of the server's GitHub App"]
    }
  end

  # ── Lines ───────────────────────────────────────────────────────────────

  attr :line, :any, required: true

  @doc "One line under a card's figure: see the module doc for the shapes."
  def line(%{line: text} = assigns) when is_binary(text) do
    ~H"""
    <div>{@line}</div>
    """
  end

  def line(%{line: {:class, class, text}} = assigns) do
    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <div class={@class}>{@text}</div>
    """
  end

  # The classes are whole strings (or the list a tone needs), never a list
  # with a nil in it: HEEx writes that nil as a space.
  def line(%{line: {:row, label, value, opts}} = assigns) do
    assigns =
      assign(assigns,
        label: label,
        value: value,
        label_attrs: if(opts[:label_class], do: [class: opts[:label_class]], else: []),
        value_class: Keyword.get(opts, :value_class, "font-mono"),
        class: Enum.join(["flex justify-between" | List.wrap(row_class(opts))], " ")
      )

    ~H"""
    <div class={@class}>
      <span {@label_attrs}>{@label}</span>
      <span class={@value_class}>{@value}</span>
    </div>
    """
  end

  def line(%{line: {:badge, label, value, class}} = assigns) do
    assigns = assign(assigns, label: label, value: value, class: class)

    ~H"""
    <div class="flex justify-between items-center">
      <span>{@label}</span>
      <span class={["badge badge-sm font-mono", @class]}>{@value}</span>
    </div>
    """
  end

  def line(%{line: {:bar, locale, percent}} = assigns) do
    assigns = assign(assigns, locale: locale, percent: percent)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="font-mono font-semibold w-12">{String.upcase(@locale)}</span>
      <div class="flex-1 bg-base-300 rounded-full h-1.5">
        <div
          class={[
            "h-1.5 rounded-full transition-all",
            if(@percent == 100.0, do: "bg-success", else: "bg-warning")
          ]}
          style={"width: #{@percent}%"}
        >
        </div>
      </div>
      <span class="font-mono text-xs w-10 text-right">{@percent}%</span>
    </div>
    """
  end

  def line(%{line: {:alert_link, text, path}} = assigns) do
    assigns = assign(assigns, text: text, path: path)

    ~H"""
    <div class="mt-3 pt-2 border-t border-base-300">
      <.link
        navigate={@path}
        class="inline-flex items-center gap-1.5 text-warning font-semibold hover:underline"
      >
        <.icon name="hero-exclamation-triangle-solid" class="w-4 h-4" />
        {@text}
      </.link>
    </div>
    """
  end

  def line(%{line: {label, nil, path}} = assigns) do
    assigns = assign(assigns, label: label, path: path)

    ~H"""
    <div><.link navigate={@path} class="link">{@label}</.link></div>
    """
  end

  def line(%{line: {label, value, path}} = assigns) do
    assigns = assign(assigns, label: label, value: value, path: path)

    ~H"""
    <div>{@label}: <.link navigate={@path} class="link">{@value}</.link></div>
    """
  end

  def line(%{line: {label, value}} = assigns) do
    assigns = assign(assigns, label: label, value: value)

    ~H"""
    <div>{@label}: {@value}</div>
    """
  end

  # ── Figures ─────────────────────────────────────────────────────────────

  defp row_class(opts) do
    Enum.reject([opts[:center] && "items-center", opts[:class]], &(&1 in [nil, false]))
  end

  defp tone(count, lit) when count > 0, do: lit
  defp tone(_count, _lit), do: "badge-ghost opacity-50"

  defp state_count(counts, state), do: Map.get(counts, state, 0)

  defp pct(nil), do: "—"
  defp pct(rate) when is_float(rate), do: "#{Float.round(rate * 100, 1)}%"

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
end
