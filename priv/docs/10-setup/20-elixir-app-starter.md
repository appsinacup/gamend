---
icon: hero-square-3-stack-3d
---

# Elixir App Starter

A ready-made starter repository. Instead of assembling this by hand, start from the maintained example repository: [github.com/appsinacup/gamend_starter](https://github.com/appsinacup/gamend_starter). Clone it, run it locally with `mix dev.start`, then customize. To deploy it, follow the [Deployment](/docs/setup?guide=deployment) guide.

## Recommended project shape

If you want to customize Gamend in Elixir, the clean model is to own a small runnable host app and pull the shared code in as dependencies. Do not depend on the umbrella root itself. The host is the extension point; core and web are the reusable packages.

```text
my_game/
  mix.exs
  config/
  assets/
  lib/
    my_game/
      application.ex
      router.ex
    game_server_web/
      endpoint.ex
      components/
      live/

# Your app owns the host/runtime layer.
# Shared functionality comes from game_server_core and game_server_web deps.
```

## Dependency boundary

A new starter app should depend on game_server_core and game_server_web, while keeping its own host code, endpoint, router, assets, config, and branding files in the new repository.

| Keep in your app | Pull from dependencies |
|---|---|
| Host router and endpoint | Domain logic from game_server_core |
| Host-owned layouts, pages, branding, and runtime config | Reusable controllers, LiveViews, channels, and plugs from game_server_web |
| Host app assets/config plus release and deploy files | Schema/context updates from upstream releases |

## Minimal mix.exs shape

The starter app should be a normal Mix project, not another umbrella root. Replace the current in_umbrella deps with versioned or path-based deps, and keep heroicons as a direct dependency because the published web package cannot declare it.

```elixir
defp deps do
  [
    # Use Hex versions once published, or path/git deps while bootstrapping
    {:game_server_core, "~> 1.0"},
    {:game_server_web, "~> 1.0"},
    {:heroicons,
     github: "tailwindlabs/heroicons",
     tag: "v2.2.0",
     sparse: "optimized",
     app: false,
     compile: false,
     depth: 1}
  ]
end
```

## What to copy into a starter repo

If you create a starter repository, keep the runtime shell small. Copy the host app as your seed, then prune infrastructure that your starter does not want to promise by default.

- Copy the current host app as the starting runtime shell
- Copy the root config/, assets/, and the static files your host actually serves
- Keep start/build scripts that make local development work out of the box
- Drop optional infra like nginx, grafana, stress tooling, or extra docs unless your starter wants to maintain them

## How to remove or add product surface

Do not think of game_server_web as something you trim file-by-file inside the dependency. If you want less product surface, remove routes, links, and host-owned pages from your starter app. If you want more, add host routes and new app code alongside the shared modules.

### Recommended long-term setup

A dedicated starter repository is better than asking users to clone the whole upstream repo and delete pieces. The starter repo should own the runnable host and developer workflow, while upstream releases provide reusable core and web packages.
