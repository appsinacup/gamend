defmodule GamendWeb.AdminLive.Pages do
  @moduledoc """
  What core's admin pages are called and how they look: the one place a page's
  title, icon and colour are written, so its tile on `/admin`, its card there
  and the heading of the page itself cannot drift apart.

  A page reads its entry by path (`<.admin_header page="/admin/users" />`, see
  `GamendWeb.AdminComponents`). A host's pages are not in this table: a host
  names them in its `GamendWeb.AdminCard` module and in its own
  `<.admin_header title=… icon=… color=… />`.

  `sections/0` is the menu on `/admin`, in order. A page reached only from
  another page is in `@subpages`: it has a heading, not a tile.
  """

  @type page :: %{
          required(:path) => String.t(),
          required(:title) => String.t(),
          required(:icon) => String.t(),
          required(:color) => String.t()
        }

  @sections [
    %{
      title: "Players",
      links: [
        %{path: "/admin/users", title: "Users", icon: "hero-users", color: "sky"},
        %{path: "/admin/sessions", title: "Sessions", icon: "hero-finger-print", color: "indigo"},
        %{path: "/admin/groups", title: "Groups", icon: "hero-user-group", color: "teal"},
        %{path: "/admin/parties", title: "Parties", icon: "hero-sparkles", color: "violet"},
        %{path: "/admin/friends", title: "Friends", icon: "hero-heart", color: "rose"},
        %{path: "/admin/blacklist", title: "Blacklist", icon: "hero-hand-raised", color: "slate"}
      ]
    },
    %{
      title: "Gameplay",
      links: [
        %{path: "/admin/lobbies", title: "Lobbies", icon: "hero-rectangle-group", color: "violet"},
        %{
          path: "/admin/leaderboards",
          title: "Leaderboards",
          icon: "hero-chart-bar",
          color: "amber"
        },
        %{path: "/admin/tournaments", title: "Tournaments", icon: "hero-trophy", color: "orange"},
        %{
          path: "/admin/matchmaking",
          title: "Matchmaking",
          icon: "hero-arrows-right-left",
          color: "cyan"
        },
        %{path: "/admin/quests", title: "Quests", icon: "hero-map", color: "emerald"},
        %{
          path: "/admin/results",
          title: "Results",
          icon: "hero-clipboard-document-check",
          color: "blue"
        }
      ]
    },
    %{
      title: "Community",
      links: [
        %{path: "/admin/chat", title: "Chat", icon: "hero-chat-bubble-left-right", color: "sky"},
        %{path: "/admin/chat/reports", title: "Chat reports", icon: "hero-flag", color: "rose"},
        %{path: "/admin/chat/filter", title: "Word filter", icon: "hero-funnel", color: "amber"},
        %{
          path: "/admin/reports",
          title: "Reports",
          icon: "hero-exclamation-triangle",
          color: "orange"
        },
        %{path: "/admin/bans", title: "Bans", icon: "hero-no-symbol", color: "rose"},
        %{path: "/admin/notifications", title: "Notifications", icon: "hero-bell", color: "violet"},
        %{
          path: "/admin/push",
          title: "Push devices",
          icon: "hero-device-phone-mobile",
          color: "indigo"
        },
        %{path: "/admin/translations", title: "Translations", icon: "hero-language", color: "teal"}
      ]
    },
    %{
      title: "Monetization",
      links: [
        %{path: "/admin/economy", title: "Economy", icon: "hero-banknotes", color: "emerald"},
        %{path: "/admin/payments", title: "Payments", icon: "hero-credit-card", color: "teal"}
      ]
    },
    %{
      title: "Data",
      links: [
        %{
          path: "/admin/analytics",
          title: "Analytics",
          icon: "hero-presentation-chart-line",
          color: "indigo"
        },
        %{path: "/admin/geo", title: "Geo Traffic", icon: "hero-globe-alt", color: "cyan"},
        %{path: "/admin/kv", title: "Key-Value", icon: "hero-circle-stack", color: "teal"},
        %{path: "/admin/storage", title: "Storage", icon: "hero-archive-box", color: "amber"},
        %{path: "/admin/retention", title: "Retention", icon: "hero-clock", color: "slate"}
      ]
    },
    %{
      title: "System",
      links: [
        %{
          path: "/admin/config",
          title: "Configuration",
          icon: "hero-wrench-screwdriver",
          color: "slate"
        },
        %{
          path: "/admin/settings",
          title: "Settings",
          icon: "hero-adjustments-horizontal",
          color: "sky"
        },
        %{path: "/admin/connections", title: "Connections", icon: "hero-signal", color: "emerald"},
        %{
          path: "/admin/rate_limiting",
          title: "Rate Limiting",
          icon: "hero-shield-exclamation",
          color: "amber"
        },
        %{path: "/admin/logs", title: "Logs", icon: "hero-document-text", color: "orange"},
        %{path: "/admin/oban", title: "Jobs", icon: "hero-queue-list", color: "violet"},
        %{path: "/admin/system", title: "System", icon: "hero-cpu-chip", color: "cyan"},
        %{path: "/admin/runtime", title: "Runtime", icon: "hero-command-line", color: "indigo"}
      ]
    }
  ]

  @subpages [
    %{path: "/admin/lobbies/live", title: "Live lobby", icon: "hero-eye", color: "violet"},
    %{
      path: "/admin/github",
      title: "GitHub installations",
      icon: "hero-code-bracket",
      color: "slate"
    }
  ]

  @by_path Map.new(
             Enum.flat_map(@sections, & &1.links) ++ @subpages,
             &{&1.path, &1}
           )

  @doc "The menu on `/admin`: sections of `%{title:, links: [page]}`, in order."
  @spec sections() :: [%{title: String.t(), links: [page()]}]
  def sections, do: @sections

  @doc "Every page in the table, the menu's and the subpages."
  @spec all() :: [page()]
  def all, do: Map.values(@by_path)

  @doc """
  The entry for a core admin path. A path that is not in the table is a typo in
  the page calling it, so it raises rather than draw an untitled heading.
  """
  @spec fetch!(String.t()) :: page()
  def fetch!(path), do: Map.fetch!(@by_path, path)
end
