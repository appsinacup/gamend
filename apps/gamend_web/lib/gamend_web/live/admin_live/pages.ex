defmodule GamendWeb.AdminLive.Pages do
  @moduledoc """
  What core's admin pages are called and how they look: the one place a page's
  title, icon and colour are written, so its card on `/admin` and the heading
  of the page itself cannot drift apart.

  A page reads its entry by path (`<.admin_header page="/admin/users" />`, see
  `GamendWeb.AdminComponents`). A host's pages are not in this table: a host
  names them in its `GamendWeb.AdminCard` module and in its own
  `<.admin_header title=… icon=… color=… />`.

  `dashboard/0` lists the pages with a card on `/admin`. A page reached only
  from another page is in `@subpages`: it has a heading, not a card.
  """

  @type page :: %{
          required(:path) => String.t(),
          required(:title) => String.t(),
          required(:icon) => String.t(),
          required(:color) => String.t()
        }

  @dashboard [
    %{path: "/admin/users", title: "Users", icon: "hero-users-solid", color: "sky"},
    %{
      path: "/admin/sessions",
      title: "Sessions",
      icon: "hero-finger-print-solid",
      color: "indigo"
    },
    %{path: "/admin/groups", title: "Groups", icon: "hero-user-group-solid", color: "teal"},
    %{path: "/admin/parties", title: "Parties", icon: "hero-sparkles-solid", color: "violet"},
    %{path: "/admin/friends", title: "Friends", icon: "hero-heart-solid", color: "rose"},
    %{
      path: "/admin/blacklist",
      title: "Blacklist",
      icon: "hero-hand-raised-solid",
      color: "slate"
    },
    %{
      path: "/admin/lobbies",
      title: "Lobbies",
      icon: "hero-rectangle-group-solid",
      color: "violet"
    },
    %{
      path: "/admin/leaderboards",
      title: "Leaderboards",
      icon: "hero-chart-bar-solid",
      color: "amber"
    },
    %{
      path: "/admin/tournaments",
      title: "Tournaments",
      icon: "hero-trophy-solid",
      color: "orange"
    },
    %{
      path: "/admin/matchmaking",
      title: "Matchmaking",
      icon: "hero-arrows-right-left-solid",
      color: "cyan"
    },
    %{path: "/admin/quests", title: "Quests", icon: "hero-map-solid", color: "emerald"},
    %{
      path: "/admin/results",
      title: "Results",
      icon: "hero-clipboard-document-check-solid",
      color: "blue"
    },
    %{
      path: "/admin/chat",
      title: "Chat",
      icon: "hero-chat-bubble-left-right-solid",
      color: "sky"
    },
    %{path: "/admin/chat/reports", title: "Chat reports", icon: "hero-flag-solid", color: "rose"},
    %{
      path: "/admin/chat/filter",
      title: "Word filter",
      icon: "hero-funnel-solid",
      color: "amber"
    },
    %{
      path: "/admin/reports",
      title: "Reports",
      icon: "hero-exclamation-triangle-solid",
      color: "orange"
    },
    %{path: "/admin/bans", title: "Bans", icon: "hero-no-symbol-solid", color: "rose"},
    %{
      path: "/admin/notifications",
      title: "Notifications",
      icon: "hero-bell-solid",
      color: "violet"
    },
    %{
      path: "/admin/push",
      title: "Push devices",
      icon: "hero-device-phone-mobile-solid",
      color: "indigo"
    },
    %{
      path: "/admin/translations",
      title: "Translations",
      icon: "hero-language-solid",
      color: "teal"
    },
    %{path: "/admin/economy", title: "Economy", icon: "hero-banknotes-solid", color: "emerald"},
    %{path: "/admin/payments", title: "Payments", icon: "hero-credit-card-solid", color: "teal"},
    %{
      path: "/admin/analytics",
      title: "Analytics",
      icon: "hero-presentation-chart-line-solid",
      color: "indigo"
    },
    %{path: "/admin/geo", title: "Geo Traffic", icon: "hero-globe-alt-solid", color: "cyan"},
    %{path: "/admin/kv", title: "Key-Value", icon: "hero-circle-stack-solid", color: "teal"},
    %{path: "/admin/storage", title: "Storage", icon: "hero-archive-box-solid", color: "amber"},
    %{path: "/admin/retention", title: "Retention", icon: "hero-clock-solid", color: "slate"},
    %{
      path: "/admin/config",
      title: "Configuration",
      icon: "hero-wrench-screwdriver-solid",
      color: "slate"
    },
    %{
      path: "/admin/settings",
      title: "Settings",
      icon: "hero-adjustments-horizontal-solid",
      color: "sky"
    },
    %{
      path: "/admin/connections",
      title: "Connections",
      icon: "hero-signal-solid",
      color: "emerald"
    },
    %{
      path: "/admin/rate_limiting",
      title: "Rate Limiting",
      icon: "hero-shield-exclamation-solid",
      color: "amber"
    },
    %{path: "/admin/logs", title: "Logs", icon: "hero-document-text-solid", color: "orange"},
    %{path: "/admin/oban", title: "Jobs", icon: "hero-queue-list-solid", color: "violet"},
    %{path: "/admin/system", title: "System", icon: "hero-cpu-chip-solid", color: "cyan"},
    %{path: "/admin/runtime", title: "Runtime", icon: "hero-command-line-solid", color: "indigo"},
    %{
      path: "/admin/dashboard",
      title: "Live Dashboard",
      icon: "hero-chart-pie-solid",
      color: "rose"
    },
    %{
      path: "/admin/github",
      title: "GitHub installations",
      icon: "hero-code-bracket-solid",
      color: "slate"
    }
  ]

  @subpages [
    %{path: "/admin/lobbies/live", title: "Live lobby", icon: "hero-eye-solid", color: "violet"}
  ]

  @by_path Map.new(@dashboard ++ @subpages, &{&1.path, &1})

  @doc "The pages with a card on `/admin`."
  @spec dashboard() :: [page()]
  def dashboard, do: @dashboard

  @doc "Every page in the table, the dashboard's and the subpages."
  @spec all() :: [page()]
  def all, do: Map.values(@by_path)

  @doc """
  The entry for a core admin path. A path that is not in the table is a typo in
  the page calling it, so it raises rather than draw an untitled heading.
  """
  @spec fetch!(String.t()) :: page()
  def fetch!(path), do: Map.fetch!(@by_path, path)
end
