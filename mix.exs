defmodule GamendHost.MixProject do
  use Mix.Project

  def project do
    [
      app: :gamend_host,
      name: "Gamend",
      version: System.get_env("GAMEND_CONTENT_APP_VERSION") || "1.0.0",
      elixir: "~> 1.20",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      # The umbrella apps carry the modules this root app calls into
      # (GamendWeb.DocsLive, GamendWeb.Sitemap.Xml). Without them in the PLT,
      # dialyzer analyses lib/ against a world where those modules do not
      # exist and reports every call as unknown_function.
      dialyzer: [plt_add_apps: [:mix, :gamend_core, :gamend_web]],
      aliases: aliases(),
      releases: releases(),
      deps: deps()
    ]
  end

  # `mix release` copies config/runtime.exs to releases/<vsn>/runtime.exs and
  # nothing else from config/. Ours is a two-line shim that requires
  # host_runtime.exs from its own directory, which in turn requires dotenv.exs
  # to read the working directory's .env, so without this step the release
  # boots into a Code.LoadError before any application starts. Ship the files
  # beside the shim that reads them.
  defp releases do
    [
      gamend_host: [
        steps: [:assemble, &copy_host_runtime_config/1, &copy_starter_env_example/1]
      ]
    ]
  end

  defp copy_host_runtime_config(release) do
    for file <- ["host_runtime.exs", "dotenv.exs"] do
      source = Path.join([__DIR__, "config", file])
      target = Path.join([release.path, "releases", release.version, file])

      File.cp!(source, target)
    end

    release
  end

  # `gamend starter` copies priv/starter/<name> into a project. The reference
  # for every setting is generated at the root (`mix gamend.settings.env_example`),
  # so it is added to each bundled template here rather than kept twice in git.
  defp copy_starter_env_example(release) do
    vsn = release.applications[:gamend_host][:vsn]
    starters = Path.join([release.path, "lib", "gamend_host-#{vsn}", "priv", "starter"])

    for template <- File.ls!(starters), File.dir?(Path.join(starters, template)) do
      File.cp!(
        Path.join(__DIR__, ".env.example"),
        Path.join([starters, template, ".env.example"])
      )
    end

    release
  end

  def application do
    [
      mod: {GamendHost.Application, []},
      extra_applications:
        [:logger, :runtime_tools, :swoosh] ++
          if(Mix.env() == :prod, do: [:os_mon], else: [])
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    [
      shared_dep(:gamend_core, "apps/gamend_core"),
      shared_dep(:gamend_web, "apps/gamend_web"),
      # The GDScript transpiler, shipped at runtime so a release with no Mix can
      # still build a GDScript plugin (`Gamend.Hooks.PluginBuilder` calls
      # `Gamend.GDScript` in-process). Its Mix tasks compile in too; they are
      # never called outside Mix.
      shared_dep(:gamend_plugin_tools, "sdk_tools"),
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:oban_web, "~> 2.11"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
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
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:guardian, "~> 2.3"},
      {:ueberauth_steam_strategy, "~> 0.2.1"},
      {:corsica, "~> 2.0"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "db.setup", "assets.setup", "assets.build"],
      "dev.start": [
        "ecto.create --quiet -r Gamend.Repo",
        "db.migrate",
        "assets.build",
        "phx.server"
      ],
      "prod.start": ["assets.deploy", "db.setup", "phx.server"],
      "db.migrate": ["host.migrate -r Gamend.Repo"],
      "db.rollback": ["host.rollback -r Gamend.Repo"],
      "db.setup": ["host.db.setup"],
      "db.reset": ["host.db.reset"],
      "db.seed": ["host.seed"],
      test:
        [
          "ecto.create --quiet -r Gamend.Repo",
          "host.migrate --quiet -r Gamend.Repo",
          "test"
        ] ++ local_web_commands([core_test_cmd("test"), web_test_cmd("test")]),
      lint:
        ["format --check-formatted", "credo --strict"] ++
          local_web_commands([web_cmd("format --check-formatted"), web_cmd("credo --strict")]) ++
          plugin_commands("format --check-formatted"),
      "deps.audit": [&prune_vendored_lockfiles/1, "deps.audit"],
      # `mix deps.update --all` only rewrites the lockfile of the project it runs
      # in. apps/*, sdk, sdk_tools and modules/plugins/* are separate Mix projects
      # with their own mix.lock, and CI builds each in its own directory, so a
      # root-only update silently leaves them pinned to stale versions.
      "deps.update.all": ["cmd bin/update-deps"],
      # The umbrella apps are path deps, so their modules sit in the *deps* PLT
      # while dialyxir keys its freshness on mix.lock alone — app source can
      # change without the hash moving. Skipping the recheck then reports every
      # function added since the PLT was built as one that does not exist. CI
      # drops the hash file for the same reason.
      dialyzer: ["dialyzer --force-check"],
      # The slow checks CI runs and `precommit` leaves out: a cold PLT is
      # minutes, and `hex.outdated` hits the network. Both also run INSIDE each
      # app, the way CI's dialyzer does: from the root, dialyzer reported 0
      # errors while CI was red on two real warnings in gamend_web, and each
      # app has its own mix.lock, which the root's `hex.outdated` does not read.
      check:
        [
          "lint",
          "dialyzer",
          # Shelled out: `hex.outdated` lives in the Hex archive, which
          # `Mix.Task.run/1` cannot resolve from inside an alias.
          "cmd env #{force_ansi()}#{child_mix()} hex.outdated"
        ] ++
          local_web_commands([
            core_cmd("dialyzer"),
            web_cmd("dialyzer"),
            core_cmd("hex.outdated"),
            web_cmd("hex.outdated")
          ]),
      # The inner loop: fast checks only. Generators and the web app's own
      precommit:
        [
          "compile --warnings-as-errors",
          "format",
          "gen.sdk",
          # Regenerate rather than --check, like format and gen.sdk above: a
          # stale settings doc is fixed and committed here, and CI runs the
          # --check form so a bypassed precommit still cannot ship one.
          "gamend.settings.env_example",
          "gamend.settings.guide",
          # Theme text lives in data, so `gettext.extract` cannot see it.
          "gamend.theme.extract",
          "test",
          # The Balaur SDK (`balaur_addons/addons/gamend`), from the OpenAPI
          # document, after `test` so the app the document needs is already up.
          # The document is gitignored, so a local copy older than the last API
          # change kept a stale SDK passing here while CI's `sdkgen balaur
          # --check` failed on it (the reports endpoints).
          "openapi.spec.json --spec GamendWeb.ApiSpec --filename clients/godot/openapi.json --pretty=true",
          "cmd python3 clients/sdkgen balaur",
          "credo --strict",
          "gamend.api.lint"
        ] ++
          local_web_commands([
            # No `xref unreachable`: Elixir folded that check into the compiler,
            # so the task prints "has no effect now" and exits 0. A step that
            # cannot fail is noise, not a gate.
            # A dependency's warnings never fail its dependent's build, so the
            # core is only gated when it is the project being compiled.
            core_test_cmd("compile --warnings-as-errors"),
            web_test_cmd("compile --warnings-as-errors"),
            web_cmd("format"),
            web_cmd("credo --strict")
          ]) ++ plugin_commands("format"),
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "tailwind gamend_web",
        "esbuild gamend_web",
        "esbuild gamend_host_hooks"
      ],
      # No `--required` on optimize_images: the release Dockerfile's builder
      # stage does not install optipng/pngquant/imagemagick, so demanding them
      # would fail every image build. Missing tools mean images ship unoptimized,
      # not that the build is broken.
      "assets.deploy": [
        "host.optimize_images",
        # After optimize_images, which rewrites the sources these are cut from.
        # A no-op until a theme/config.json image declares "widths".
        "host.responsive_images",
        "tailwind gamend_web --minify",
        "esbuild gamend_web --minify",
        "esbuild gamend_host_hooks --minify",
        # Last: phx.digest hashes whatever bytes are on disk, so anything that
        # rewrites an asset has to have run already.
        "phx.digest",
        # After the digest, because it is the hashed copies that get served.
        # phx.digest writes .gz; this adds the .br that brotli_static wants.
        "cmd bin/compress-static"
      ]
    ]
  end

  # mix_audit's `apps/**/mix.lock` glob also matches lockfiles vendored inside
  # git dependencies (pigeon ships one). A dependency's own lock never drives our
  # resolution — ours does — so scanning it only reports false positives.
  defp prune_vendored_lockfiles(_args) do
    "apps/**/mix.lock"
    |> Path.wildcard()
    |> Enum.filter(&(&1 =~ ~r{(^|/)deps/}))
    |> Enum.each(&File.rm/1)
  end

  # `mix cmd` pipes the child's stdio, so the child BEAM boots with ANSI off
  # and cmd-wrapped steps lose color even on a TTY. Forward this process's own
  # color state; the web app's config.exs honors FORCE_ANSI. On CI (no TTY)
  # nothing is set and logs stay escape-free.
  defp force_ansi, do: if(IO.ANSI.enabled?(), do: "FORCE_ANSI=true ", else: "")

  # `mix cmd` starts its child in a session of its own, so Ctrl+C reaches only
  # this VM: the child outlives it, re-parented to launchd, still running.
  # The child's stdin is a pipe from this VM, closed when it dies, so the
  # child halts on EOF. Use this, never a bare `mix`, in every `cmd`.
  defp child_mix, do: "elixir -e 'spawn(fn -> IO.read(:eof); System.halt(1) end)' -S mix"

  defp web_cmd(task), do: "cmd --cd #{web_app_path()} env #{force_ansi()}#{child_mix()} #{task}"

  defp web_test_cmd(task),
    do: "cmd --cd #{web_app_path()} env MIX_ENV=test #{force_ansi()}#{child_mix()} #{task}"

  defp core_cmd(task), do: "cmd --cd apps/gamend_core env #{force_ansi()}#{child_mix()} #{task}"

  # The core's own suite: the context tests that need no web app to run.
  defp core_test_cmd(task),
    do: "cmd --cd apps/gamend_core env MIX_ENV=test #{force_ansi()}#{child_mix()} #{task}"

  defp local_web_commands(commands) do
    if local_web_source?(), do: commands, else: []
  end

  # Plugins, the SDK and its tooling are their own mix projects, so neither the
  # umbrella's formatter inputs nor `local_web_commands/1` reach them. Without
  # this, a misformatted one passes `precommit` and fails on CI, which does walk
  # `modules/plugins/*`. Absent in a host checkout, which has none of them.
  defp plugin_commands(task) do
    for dir <- plugin_paths(), do: "cmd --cd #{dir} env #{force_ansi()}#{child_mix()} #{task}"
  end

  defp plugin_paths do
    (bundled_projects("modules/plugins") ++
       bundled_projects("modules/plugins_examples") ++ ["sdk", "sdk_tools"])
    |> Enum.filter(&File.regular?(Path.join(&1, "mix.exs")))
  end

  defp bundled_projects(root) do
    case File.ls(root) do
      {:ok, entries} -> entries |> Enum.sort() |> Enum.map(&Path.join(root, &1))
      {:error, _not_a_checkout_with_plugins} -> []
    end
  end

  defp local_web_source?, do: File.dir?("apps/gamend_web")

  defp web_app_path, do: shared_app_path(:gamend_web, "apps/gamend_web")

  defp shared_app_path(app, fallback) do
    dep_root = Mix.Project.deps_paths()[app]
    nested_dep_path = dep_root && Path.join(dep_root, fallback)

    cond do
      File.dir?(fallback) -> fallback
      nested_dep_path && File.dir?(nested_dep_path) -> nested_dep_path
      dep_root -> dep_root
      true -> fallback
    end
  end

  defp shared_dep(app, local_path) do
    if File.dir?(local_path) do
      {app, path: local_path}
    else
      {app, github: "appsinacup/gamend", sparse: local_path, override: true}
    end
  end
end
