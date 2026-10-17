defmodule GamendWeb.MixProject do
  use Mix.Project

  @version "1.0.5"
  @source_url "https://github.com/appsinacup/gamend"

  def project do
    [
      app: :gamend_web,
      version: System.get_env("GAMEND_CONTENT_APP_VERSION") || @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      dialyzer: [plt_add_apps: [:mix]],
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # The core's test support (DataCase, fixtures, the test runtime) lives with
  # the core suite and is shared from there, not copied.
  defp elixirc_paths(:test),
    do: ["lib", "test/support", Path.expand("../gamend_core/test/support", __DIR__)]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:gamend_core, path: "../gamend_core"},
      {:phoenix, "~> 1.8.3"},
      {:protobuf, "~> 0.17"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:phoenix_live_view, "~> 1.2.1"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:oban_web, "~> 2.11"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      # dev/test only, and deliberately so: heroicons is a GitHub-only dep, and
      # Hex reads requirements from the published environments alone — a
      # runtime entry here would make gamend_web unpublishable. The
      # host/consumer app still declares heroicons in its own mix.exs and runs
      # `assets.setup` to make the icon CSS available to the shared tailwind
      # plugin in apps/gamend_web/assets/vendor/heroicons. This copy is the one
      # `GamendWeb.Icons` embeds when the app is compiled on its own, with no
      # host deps directory to look in: its standalone test suite, and the docs
      # build inside `mix hex.publish`.
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1,
       only: [:dev, :test],
       runtime: false},
      {:swoosh, "~> 1.20"},
      {:gen_smtp, "~> 1.0"},
      {:req, "~> 0.6"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      {:ueberauth_apple, "~> 0.7"},
      {:bandit, "~> 1.9"},
      {:ueberauth, "~> 0.10"},
      {:open_api_spex, "~> 3.22"},
      {:credo, ">= 1.7.16", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:guardian, "~> 2.3"},
      {:ueberauth_steam_strategy, "~> 0.2.2"},
      {:corsica, "~> 2.0"},
      {:hammer, "~> 7.2"},
      {:hammer_backend_redis, "~> 7.1"},
      {:ex_webrtc, "~> 0.17.0"},
      {:ex_sctp, "~> 0.1.3"},
      {:prom_ex, "~> 1.12"},
      {:geolix, "~> 2.0"},
      {:geolix_adapter_mmdb2, "~> 0.6"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "compile --force",
        "test"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind gamend_web", "esbuild gamend_web"],
      "assets.deploy": [
        "tailwind gamend_web --minify",
        "esbuild gamend_web --minify",
        "phx.digest"
      ],
      lint: ["format --check-formatted", "credo --strict"],
      # gamend_core is a path dep, so its modules sit in the *deps* PLT while
      # dialyxir keys its freshness on mix.lock alone — core source can change
      # without the hash moving. Skipping the recheck then reports every core
      # function added since the PLT was built as one that does not exist. CI
      # drops the hash file for the same reason.
      dialyzer: ["dialyzer --force-check"],
      precommit: [
        "compile --warnings-as-errors",
        "xref unreachable",
        "format",
        "gen.sdk",
        "test",
        "credo --strict"
      ]
    ]
  end

  defp description do
    """
    Web interface for Gamend, built with Phoenix Framework. Provides APIs, authentication, real-time features, and payments.
    """
  end

  defp package do
    [
      name: "gamend_web",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      # A host builds its own CSS/JS bundle from these: Tailwind scans
      # `assets/js` and `lib` for classes, and `assets/vendor` holds the shared
      # plugins (heroicons, daisyUI) its app.css loads. `priv/static/flags` is
      # served straight out of this app by the endpoint's bundled-static plug,
      # alongside the fonts.
      files: ~w(lib assets/js assets/vendor assets/tsconfig.json priv/gettext
                priv/static/fonts priv/static/flags .formatter.exs mix.exs
                README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "../../CHANGELOG.md"],
      # Two audiences share this package: a host app calls a handful of
      # modules, everything else is mounted by the route macros. One flat list
      # of 200+ modules hides that distinction entirely.
      groups_for_modules: module_groups()
    ]
  end

  defp module_groups do
    [
      "Host integration": [
        GamendWeb,
        GamendWeb.Router.Shared,
        GamendWeb.Endpoint,
        GamendWeb.UserAuth,
        GamendWeb.Layouts,
        GamendWeb.CoreComponents,
        GamendWeb.Telemetry,
        GamendWeb.Router
      ],
      "Plugs & mounts": [~r/^GamendWeb\.(Plugs|OnMount|Auth)/],
      "REST API": [~r/^GamendWeb\.(Api\.|Schemas\.|ApiSpec|.*Controller$|.*HTML$|.*JSON$)/],
      Channels: [~r/^GamendWeb\.(.*Channel|UserSocket|Presence|WebRTCPeer)/],
      Admin: [~r/^GamendWeb\.AdminLive/],
      "Player pages": [~r/^GamendWeb\.(\w*Live($|\.)|LiveHelpers|PresentationPage|PageHTML)/],
      Helpers: [
        ~r/^GamendWeb\.(Helpers|Serializers|Pagination|Components|Gettext|EventCodec|SRI)/
      ],
      # Observability and runtime plumbing a host runs but rarely calls.
      Runtime: [
        ~r/^GamendWeb\.(PromEx|Telemetry|RateLimit|ConnectionTracker|AdminLogBuffer|FileLogHandler|IpBanSync|HostSupervision|RuntimeIntrospection|RealtimeEvents|GeoCountryCleaner|HostContentStatic|HostLayouts)/
      ]
    ]
  end
end
