defmodule GameServerCore.MixProject do
  use Mix.Project

  @version "1.0.7"
  @source_url "https://github.com/appsinacup/game_server"

  def project do
    [
      app: :game_server_core,
      version: System.get_env("GAMEND_CONTENT_APP_VERSION") || @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      dialyzer: [plt_add_apps: [:mix]],
      deps: deps(),
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

  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:nebulex, "~> 3.0.0-rc.2"},
      {:nebulex_local, "~> 3.0.0-rc.2"},
      {:nebulex_distributed, "~> 3.0.0-rc.2"},
      {:nebulex_redis_adapter, "~> 3.0.0-rc.2"},
      {:decorator, "~> 1.4"},
      {:phoenix, "~> 1.8.3"},
      {:protobuf, "~> 0.17"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13.3"},
      {:ecto_sqlite3, "~> 0.12"},
      {:postgrex, ">= 0.0.0"},
      {:swoosh, "~> 1.20"},
      {:gen_smtp, "~> 1.0"},
      {:req, "~> 0.6"},
      {:stripity_stripe, "~> 3.3"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:ueberauth, "~> 0.10"},
      {:ueberauth_discord, "~> 0.7"},
      {:ueberauth_apple, github: "appsinacup/ueberauth_apple", branch: "master"},
      {:ueberauth_google, "~> 0.12"},
      {:ueberauth_facebook, "~> 0.10"},
      {:ueberauth_steam_strategy, "~> 0.1.6"},
      {:jose, "~> 1.11"},
      {:guardian, "~> 2.3"},
      {:oban, "~> 2.19"},
      # Pinned past the released 2.0.1: main replaced kadabra+httpoison with
      # mint (#296), which also avoids a conflict with ueberauth_steam_strategy's
      # httpoison ~> 3.0 pin. Re-point at hex on the next pigeon release.
      {:pigeon, github: "codedge-llc/pigeon", ref: "712d5c2b20100d56bed08efed42e4eed924c422a"},
      {:goth, "~> 1.4"},
      # crontab was pulled in transitively by quantum; the Schedule tick worker
      # still parses/matches cron expressions with it.
      {:crontab, "~> 1.1"},
      {:corsica, "~> 2.0"},
      {:mdex, "~> 0.13"},
      # Syntax highlighting engine MDEx delegates to; without it fenced code
      # renders as undifferentiated text.
      {:lumis, "~> 0.1"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Core functionality for Gamend GameServer, including user management, authentication, friends, matchmaking, and more.
    """
  end

  defp package do
    [
      name: "game_server_core",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv/repo .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "../../CHANGELOG.md"],
      # Group GameServer.Hooks callbacks by entity (User / Lobby / Group / …)
      # instead of one alphabetical list. Same classifier as the SDK docs and
      # the admin runtime page.
      groups_for_docs: hook_doc_groups(),
      # Forty-odd modules in one alphabetical list buries the dozen that are
      # actually entry points, so group them the way the guides do.
      groups_for_modules: module_groups()
    ]
  end

  defp module_groups do
    [
      Accounts: [~r/^GameServer\.(Accounts|Apple|OAuth)/],
      Lobbies: [~r/^GameServer\.Lobb(ies|ySnapshots)/],
      Matchmaking: [~r/^GameServer\.(Matchmaking|ReadyChecks)/],
      Social: [~r/^GameServer\.(Friends|Groups|Parties|Chat)/],
      Progression: [~r/^GameServer\.(Quests|Leaderboards|Tournaments)/],
      Economy: [~r/^GameServer\.(Economy|Inventory|Payments)/],
      "Storage & content": [~r/^GameServer\.(KV|Storage|Content|Theme|Settings)/],
      Delivery: [~r/^GameServer\.(Notifications|Push|Realtime)/],
      Plugins: [~r/^GameServer\.Hooks/],
      Operations: [
        ~r/^GameServer\.(Retention|IpBans|Limits|Jobs|Schedule|Cache|Repo|Async|Config|Env|Lock|Mailer)/
      ],
      # Building blocks a plugin rarely touches directly.
      Internals: [~r/^GameServer\.(Schema|Types|UUIDv7|Proto)/]
    ]
  end

  @hook_groups ~w(Lifecycle User Lobby Group Party Chat Quest Leaderboard Tournament
                  Matchmaking ReadyCheck Payments Economy Push KV)

  defp hook_doc_groups do
    for group <- @hook_groups do
      {:"#{group} hooks",
       fn meta -> meta[:kind] == :callback and hook_group(to_string(meta[:name])) == group end}
    end
  end

  defp hook_group(name) do
    cond do
      name in ~w(after_startup before_stop on_custom_hook) -> "Lifecycle"
      String.contains?(name, "kv") -> "KV"
      String.contains?(name, "chat") -> "Chat"
      String.contains?(name, "quest") -> "Quest"
      String.contains?(name, "score") -> "Leaderboard"
      String.contains?(name, "matchmaking") -> "Matchmaking"
      String.contains?(name, "ready_check") -> "ReadyCheck"
      String.contains?(name, "push") -> "Push"
      String.contains?(name, "tournament") -> "Tournament"
      String.contains?(name, "purchase") or String.contains?(name, "entitlement") -> "Payments"
      String.contains?(name, "wallet") or String.contains?(name, "inventory") -> "Economy"
      String.contains?(name, "party") -> "Party"
      String.contains?(name, "group") -> "Group"
      String.contains?(name, "lobby") -> "Lobby"
      String.contains?(name, "user") -> "User"
      true -> "Other"
    end
  end
end
