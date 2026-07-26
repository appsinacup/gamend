# GameServer Web

The web layer of [Gamend](https://gamend.appsinacup.com) — the REST API,
WebSocket channels, player-facing LiveViews and the `/admin` console.
`game_server_core` holds the domain logic this sits on.

This is the package a **host app** consumes. Core is what a *plugin* calls to
add game rules; web is what your own Phoenix app mounts to get a server. The
two audiences barely overlap.

## What a host app uses

| Module | Role |
|---|---|
| `GameServerWeb.Router.Shared` | The route macros. Import it and mount the groups you want - leaving one out is how you ship a smaller API surface. Start here. |
| `GameServerWeb` | The `use GameServerWeb, :controller` / `:live_view` / `:html` macros, so host modules get the same imports and layouts. |
| `GameServerWeb.UserAuth` | Session plugs and the `on_mount` hooks behind authenticated and admin routes. |
| `GameServerWeb.Layouts` | The app and root layouts, including navigation driven by your theme config. |
| `GameServerWeb.CoreComponents` | The shared component set - `<.input>`, `<.timestamp>`, `<.pagination>`, `<.icon>` and friends. |
| `GameServerWeb.Endpoint` | Sockets, static serving and the plug stack, if you do not supply your own. |
| `GameServerWeb.OnMount.*`, `GameServerWeb.Plugs.*` | Locale, theme, colour mode, connection tracking, feature gates and rate limiting. |

Everything else — controllers, channels, admin LiveViews — is mounted by those
route macros rather than called directly.

## Installation

Add `game_server_web` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:game_server_web, "~> 1.0.0"}
  ]
end
```

The package includes `priv/gettext` (translations), `priv/static/fonts` (Inter woff2), `priv/static/images` (logos/banners), `priv/static/.well-known` (app association examples), `robots.txt`, and `favicon.ico`. Compiled JS/CSS (`priv/static/assets/`) and game assets (`priv/static/game/`) are excluded — host apps compile their own assets.

## Icons when consuming from Hex

`game_server_web` templates use `<.icon name="hero-..." />`, which renders CSS classes like `hero-x-mark`.

When publishing to Hex, CI strips the GitHub `:heroicons` dependency from the package metadata (Hex only accepts Hex deps), so host apps should provide icon generation themselves.

Recommended setup in your host app:

1. Add Heroicons to host deps:

```elixir
{:heroicons,
 github: "tailwindlabs/heroicons",
 tag: "v2.2.0",
 sparse: "optimized",
 app: false,
 compile: false,
 depth: 1}
```

2. Ensure your Tailwind CSS includes the Heroicons plugin. If you copy the host shell from this repo, keep the small resolver wrappers in `assets/vendor/` and reference:

```css
@plugin "../vendor/heroicons";
```

That wrapper resolves the shared plugin from either `apps/game_server_web` or `deps/game_server_web`.

If you wire things up manually, the shared plugin lives in `apps/game_server_web/assets/vendor/heroicons.js`.

For this monorepo layout (host app at repo root):

```css
@plugin "../../apps/game_server_web/assets/vendor/heroicons";
```

For starter/fork layouts where `game_server_web` is installed as a dependency:

```css
@plugin "../../deps/game_server_web/assets/vendor/heroicons";
```

3. If you extract this into a standalone host app, keep either the shared asset tree with the reusable web package or the host-side resolver wrappers so the plugin can still find `deps/heroicons/optimized`.

If you want your own icon set, keep compatibility by either:
- providing CSS for the same `hero-*` class names used by templates, or
- replacing icon names/component usage in your fork.
