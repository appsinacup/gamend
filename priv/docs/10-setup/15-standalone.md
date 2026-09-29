---
icon: hero-arrow-down-tray
---

# Download and run

Gamend ships as a download: one folder with the server, the Erlang runtime and
every native library inside it. Nothing else to install, no Elixir, no Docker.
You point it at a **project folder** (your theme, pages, plugins and settings)
and run `gamend start`.

| Download | Runs on |
|---|---|
| `gamend-macos-arm64` | macOS on Apple silicon |
| `gamend-linux-x86_64` | Linux x86_64, glibc 2.35 or newer (Ubuntu 22.04+, Debian 12+, Fedora 36+, RHEL 10) |
| `gamend-linux-arm64` | Linux arm64, same glibc |

Each comes in two builds, because the database is chosen when the server is
built: SQLite (the default, a file in the project, nothing to run beside it)
and `-postgres`. Windows and Intel Macs can use the [Docker image](/docs/deployment).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/appsinacup/gamend/main/scripts/install.sh | sh
```

It downloads the build for your machine into `~/.gamend` and links `gamend`
into `~/.local/bin`. `GAMEND_ADAPTER=postgres` picks the Postgres build;
`GAMEND_VERSION`, `GAMEND_INSTALL_DIR` and `GAMEND_BIN_DIR` change the rest.

Or download an archive from the
[server-latest release](https://github.com/appsinacup/gamend/releases/tag/server-latest),
unpack it anywhere and run `gamend/bin/gamend`. The macOS build is signed and
notarized.

## Start a project

```bash
mkdir my-game && cd my-game
gamend starter
gamend start
```

`gamend starter` copies a small example site into the folder and writes a
`.env` with a fresh secret key. `gamend start` creates the database, runs the
migrations and serves on [localhost:4000](http://localhost:4000). The first
account you register is the admin.

Every path is relative to the folder you run `gamend` in, so a project is a
folder you can keep in git and copy between machines. Upgrading means
installing a newer `gamend` and starting it in the same folder; the migrations
run on start.

## The project folder

Everything is optional: from an empty folder with only a `.env`, the server
runs with its built-in pages and no theme.

| Path | What it is |
|---|---|
| `.env` | Settings and secrets. Every setting, with its default, is in `.env.example`; real environment variables win over the file |
| `theme/config.json` | Title, home page, menus and footer ([Theme](/docs/theme)) |
| `static/` | Files served as they are: `static/images/…` at `/images/…`, `favicon.ico`, `robots.txt`, `theme.css`, a web build of your game in `static/game/` at `/play` |
| `blog/` | Posts, one markdown file each (`2026-01-01-welcome.md`) |
| `priv/docs/` | Guides at `/docs/<name>`, in numbered folders |
| `CHANGELOG.md`, `ROADMAP.md` | The `/changelog` and `/roadmap` pages |
| `modules/plugins/` | Server plugins in Elixir or GDScript, built with `gamend plugin.bundle` ([Server scripting](/docs/server-scripting)). The starter has one, `hello` |
| `priv/repo/seeds.exs` | Optional: an Elixir script `gamend db.setup` and `gamend db.seed` run, to create fixed data (a leaderboard your tests expect, say) |
| `db/` | The SQLite database |
| `priv/storage/` | Uploaded files, with the local storage adapter |
| `.gamend/` | The running server's state: its node cookie and, for `gamend daemon`, its logs |

A file in `static/` wins over the server's own file at the same path, so
`static/favicon.ico` replaces Gamend's icon. The theme and the markdown are
read once and kept in memory: after editing them, run `gamend reload` (or
restart) and the site shows the change.

What a download cannot change is the stylesheet: it is compiled when the server
is built, so a Tailwind class that the server itself never uses does nothing
in your markdown. Colours and fonts go in `static/theme.css`. For full control
of the code, use the [Elixir app starter](/docs/elixir-app-starter).

## Commands

The database and seed commands have the same names as the `mix` tasks of a
checkout, and run the same code.

| Command | What it does |
|---|---|
| `gamend start` | Create the database if needed, migrate, then run the server in the foreground |
| `gamend daemon` | The same, in the background; logs in `.gamend/tmp/log` |
| `gamend stop`, `gamend restart` | Stop or restart the server started from this folder |
| `gamend reload` | Re-read `theme/config.json` and the markdown on the running server |
| `gamend remote` | An Elixir shell inside the running server |
| `gamend db.setup` | Create the database, migrate, run `priv/repo/seeds.exs` |
| `gamend db.migrate` | Run pending migrations |
| `gamend db.rollback` | Roll back the last migration; `--step N`, `--to VERSION`, `--all` |
| `gamend db.reset` | Drop the database and set it up again |
| `gamend db.seed` | Run `priv/repo/seeds.exs` |
| `gamend demo.seed` | Fill the database with demo players, leaderboards, groups and more; `--count N`, `--only leaderboard,group`, `--clean` removes them |
| `gamend plugin.bundle [NAME]` | Build the plugins in `modules/plugins`, Elixir or GDScript, with the compiler inside the download; restart to load them |
| `gamend starter [TEMPLATE]` | Copy a starter into the folder, never overwriting a file unless `--force` |
| `gamend version`, `gamend help` | |

`gamend db.seed` and `gamend demo.seed` can run while the server is up.

## Templates

`gamend starter` takes the name of a template, a path to a folder or a
`.tar.gz`, or a URL:

- `default`: a small site to edit, with one page, one post and one guide.
- `website`: the gamend.org website itself, with its theme, guides, blog and
  demo game, downloaded from the release.
- `https://…/my-site.tar.gz`: any project folder packed with
  `tar czf my-site.tar.gz my-site/`, which is how a team shares a starting
  point.

Because it never overwrites, running it on an existing project only adds the
files it is missing.

## Settings

Settings come from the environment and from `.env`, named
`GAMEND_<GROUP>_<NAME>`; the [Settings reference](/docs/settings) lists them
all. The ones a download usually needs:

```bash
GAMEND_AUTH_SECRET_KEY_BASE=…      # written by `gamend starter`
GAMEND_HTTP_PORT=4000
GAMEND_HTTP_HOST=play.example.com  # the public host name, for links and cookies
GAMEND_DB_URL=ecto://user:pass@localhost/my_game   # the -postgres build only
```

On a public server, put a reverse proxy with TLS in front of it (Caddy, nginx)
or set the `GAMEND_TLS_*` settings.

## End-to-end tests and CI

A local server is the easiest thing for a game client's tests to talk to:
start it once, point the client at `http://127.0.0.1:4000`, and every test
gets a real backend of its own. `GAMEND_RATELIMIT_ENABLED=false` lifts the
rate limits a test suite would otherwise hit.

Locally:

```bash
cd test-server && gamend starter && gamend daemon
GAMEND_URL=http://127.0.0.1:4000 cargo test     # or your test runner
gamend stop
```

In GitHub Actions, the `setup-gamend` action installs the server, creates a
project and starts it in the background, then sets `GAMEND_URL` for the
following steps:

```yaml
- uses: appsinacup/gamend/actions/setup-gamend@main
  with:
    seed: --count 20          # optional: `gamend demo.seed` arguments
    env: |                    # optional: extra settings
      GAMEND_RATELIMIT_ENABLED=false
- run: cargo test --test client_live   # reads GAMEND_URL
```

| Input | Default | |
|---|---|---|
| `version` | `server-latest` | Release tag to install |
| `adapter` | `sqlite` | `postgres` also needs `GAMEND_DB_URL` in `env` and a Postgres service |
| `starter` | `default` | Template for the project; empty for none |
| `port` | `4000` | |
| `env` | | Extra `KEY=VALUE` lines for the project's `.env` |
| `seed` | | Arguments for `gamend demo.seed`, run once the server is up |
| `start` | `true` | `false` only installs and creates the project |

Its outputs are `url` and `project`, the folder to run `gamend` commands in.

## How it works

The download is an OTP release, the same one the `-slim` Docker images run,
with OpenSSL and libsrtp linked into it rather than loaded from the system.
`gamend` wraps the release's own script: `start`, `daemon`, `stop` and
`remote` pass through to it, and the other commands run inside the release
with the application's code (`GamendWeb.CLI`). Each project folder gets its
own node name and a private cookie in `.gamend/cookie`, and the node accepts
connections from the same machine only, so two projects on one machine do not
collide and nobody can reach the server's shell over the network.
