# Base images

What every Gamend image, and every host app built on Gamend, repeated in its
own Dockerfile, written once here and published to GHCR by core's CI
(`.github/workflows/base-images.yml`) for `linux/amd64` and `linux/arm64`, on
every push to `main` and weekly for Debian's security fixes.

| Image | Tag | What it is |
| --- | --- | --- |
| `ghcr.io/appsinacup/gamend-builder` | `elixir-1.20` | Elixir 1.20 on Debian 13, the system packages, Rust, Hex and Rebar, and the helpers below. The `builder` stage, and the `full` image itself |
| `ghcr.io/appsinacup/gamend-runtime` | `trixie` | Debian 13 with what an OTP release links against, and `gamend-release-start`. The `release` stage |
| `ghcr.io/appsinacup/gamend-backup` | `18` | Postgres 18 with the daily verified dump as its entrypoint (`backup/README.md`). The tag is the Postgres major, and has to be the database's |

Each also has `latest`. Core's own `Dockerfile` is built on the first two.

## An app's Dockerfile

Every app has the same one, core's included, written by
`mix gamend.gen.dockerfile` from the app's `mix.exs`: its path dependencies,
its compile-time config, its release, and `gamend_dockerfile:` for the rest
(`db_adapter:`, `plugins_dir:`, `build_args:`). `--check` fails when the file
drifted from them; nothing in it is edited by hand.

```sh
mix gamend.gen.dockerfile           # write Dockerfile
mix gamend.gen.dockerfile --check   # in CI
```

Its targets are `release` (the default, its last stage: an OTP release on
`gamend-runtime`, what a host such as Gamend Cloud runs) and `full` (`--target
full`: the builder, running `mix phx.server`). An app's own build steps, such
as fetching an engine build or the docs, go in its `assets.deploy` alias; a new
`SYNC` build arg (`--build-arg SYNC=$(date +%s)` in `deploy.conf`'s
`BUILD_ARGS`) runs that step again on every deploy, and `build_args:` declares
any ARG it reads (`"ENGINE_TAG=nightly"`).

## The helpers

In `gamend-builder` (`builder/bin/`):

| Command | Does |
| --- | --- |
| `gamend-build-plugins [flags]` | `mix deps.get`, `compile` and `plugin.bundle [flags]` in every plugin under `$GAMEND_CONTENT_PLUGINS_DIR`, skipping one the app already compiled as a path dependency. `--no-deps` first skips the fetch |
| `gamend-copy-static <otp_app> [--require]` | copies the digested `priv/static` into `_build/$MIX_ENV/lib/<otp_app>/priv/static`, where Plug.Static and a release read it. Without `--require`, no digest (a dev build) is skipped |
| `gamend-stage-release <release>` | after `mix release`, copies into the release what it reads from its working directory: `theme/`, `content/`, `blog/`, `priv/docs/`, `CHANGELOG.md`, `ROADMAP.md`, `modules/` (a host's theme config) and the plugins (without their `_build`), each when the app has it, and a `VERSION` file; then has the release write `gamend-metadata.json` beside them (`Gamend.Release.Metadata`: its Gamend's version and what it declares, for a host to read without booting it). The `release` stage then takes the one directory |
| `gamend-start` | the `full` image's command: raises the open-files limit, rebuilds the plugins when `GAMEND_START_PLUGINS=1`, creates the database when it can, then `mix do db.migrate + phx.server` in one VM. `GAMEND_ERLANG_NODE=name@host` (with `RELEASE_COOKIE`) starts a named node |

In `gamend-runtime` (`runtime/bin/`):

| Command | Does |
| --- | --- |
| `gamend-release-start <release>` | raises the open-files limit, runs `Gamend.Release.prepare/0` (create when it can, migrate), then `bin/<release> start`. The generated Dockerfile passes `$GAMEND_RELEASE` |

## Changing one

A change here reaches an app at its next build: `docker compose build --pull`,
which every app's `rebuild.sh` runs, pulls the new tag. A package that is new on
GHCR is private until someone makes it public (the package's settings,
"Change visibility"), and a host pulling it anonymously gets `unauthorized`.

What belongs here is what every Gamend image needs. A package only one app uses
goes in that app's Dockerfile, on top of the builder.
