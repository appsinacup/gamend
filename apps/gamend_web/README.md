# Gamend Web

The web layer of [Gamend](https://gamend.org) — the REST API,
WebSocket channels, player-facing LiveViews and the `/admin` console.
`gamend_core` holds the domain logic this sits on.

This is the package a **host app** consumes. Core is what a *plugin* calls to
add game rules; web is what your own Phoenix app mounts to get a server. The
two audiences barely overlap.

## What a host app uses

| Module | Role |
|---|---|
| `GamendWeb.Router.Shared` | The route macros. Import it and mount the groups you want - leaving one out is how you ship a smaller API surface. Start here. |
| `GamendWeb` | The `use GamendWeb, :controller` / `:live_view` / `:html` macros, so host modules get the same imports and layouts. |
| `GamendWeb.UserAuth` | Session plugs and the `on_mount` hooks behind authenticated and admin routes. |
| `GamendWeb.Layouts` | The app and root layouts, including navigation driven by your theme config. |
| `GamendWeb.CoreComponents` | The shared component set - `<.input>`, `<.timestamp>`, `<.pagination>`, `<.icon>` and friends. |
| `GamendWeb.Endpoint` | Sockets, static serving and the plug stack, if you do not supply your own. |
| `GamendWeb.OnMount.*`, `GamendWeb.Plugs.*` | Locale, theme, colour mode, connection tracking, feature gates and rate limiting. |

Everything else — controllers, channels, admin LiveViews — is mounted by those
route macros rather than called directly.

## Installation

Add `gamend_web` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gamend_web, "~> 1.1"}
  ]
end
```

The package includes `priv/gettext` (translations), `priv/static/fonts` (Inter woff2), `priv/static/images` (logos/banners), `priv/static/.well-known` (app association examples), `robots.txt`, and `favicon.ico`. Compiled JS/CSS (`priv/static/assets/`) and game assets (`priv/static/game/`) are excluded — host apps compile their own assets.

## Icons when consuming from Hex

`gamend_web` templates use `<.icon name="hero-..." />`, which renders CSS classes like `hero-x-mark`.

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

That wrapper resolves the shared plugin from either `apps/gamend_web` or `deps/gamend_web`.

If you wire things up manually, the shared plugin lives in `apps/gamend_web/assets/vendor/heroicons.js`.

For this monorepo layout (host app at repo root):

```css
@plugin "../../apps/gamend_web/assets/vendor/heroicons";
```

For starter/fork layouts where `gamend_web` is installed as a dependency:

```css
@plugin "../../deps/gamend_web/assets/vendor/heroicons";
```

3. If you extract this into a standalone host app, keep either the shared asset tree with the reusable web package or the host-side resolver wrappers so the plugin can still find `deps/heroicons/optimized`.

If you want your own icon set, keep compatibility by either:
- providing CSS for the same `hero-*` class names used by templates, or
- replacing icon names/component usage in your fork.
