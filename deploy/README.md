# Deploying an app on its own host

`gamend-deploy` deploys a docker compose app on the machine it runs on: it
checks the host, builds, starts, waits until the app is healthy and prunes old
build cache. Every app uses this one script. What is the app's own lives in a
`deploy.conf` at its checkout's root, and a copy of `rebuild.sh` (this
directory's) starts it:

```sh
./rebuild.sh            # pull, check, build, start, prune
./rebuild.sh --check    # pull, then the checks alone
./rebuild.sh --no-pull  # deploy what is checked out now
./rebuild.sh --export DIR   # .env and the database into DIR, for Gamend Cloud
```

`--export` writes what Gamend Cloud imports a server from
(`GamendCloud.Imports`), every file mode 600: `.env` as it is; `gamend.dump`,
`pg_dump -Fc` of the running `DB_SERVICE` (`db` unless deploy.conf sets it), on
Postgres; and what only the app can copy (`Gamend.Export`, in a one-off
container of its image): `gamend.db` on SQLite and `files.tar`, its stored
files with `storage/` inside (`EXPORT_FILES=0` leaves them out, for a host
whose folders move with it). The app's `app_export DIR` hook adds anything
else. It stops nothing: for the last export before a move, stop the app first.

`rebuild.sh` pulls the checkout first, so the checks and the deploy are the new
code's, then fetches `gamend-deploy` from this repository at the version
`deploy.conf` names (`GAMEND_DEPLOY_REF`): a commit is fetched once and kept in
`~/.cache/gamend-deploy/`, a branch on every deploy. `GAMEND_DEPLOY=/path/to/gamend-deploy`
runs a local file instead, to try a change.

## deploy.conf

Bash, sourced after `.env` is read, so its values can use `.env`'s. Every
setting is optional; each check runs only when its setting asks for it.

```bash
GAMEND_DEPLOY_REF=main                   # a commit to pin, or a branch

COMPOSE_FILES="docker-compose.prod.yml"  # default docker-compose.yml
APP_SERVICE=app                          # the service the hints name
REQUIRED_ENV="POSTGRES_PASSWORD GAMEND_AUTH_SECRET_KEY_BASE"   # a stop when unset
RECOMMENDED_ENV="GAMEND_HTTP_HOST"       # a warning when unset
REQUIRED_FILES="monitoring/secrets/metrics_token"
CHECK_SECRETS_KEYS=1                     # GAMEND_SECRETS_KEYS set and well formed
CHECK_PODMAN=rootless                    # PODMAN_SOCKET is the user's own socket

BIND_ADDRESS=${APP_BIND_ADDR:-}          # the one address this stack binds 80/443 on
REQUIRE_BIND_ADDRESS=1                   # empty is a stop
BIND_ADDRESS_HINT="APP_BIND_ADDR=192.168.1.10"
TLS_HOST=example.org                     # warn under TLS_WARN_DAYS (14) left

PUBLIC_IP=${PUBLIC_IP_IN_ENV:-}          # warn when a name points elsewhere
DNS_NAMES="example.org www.example.org"

PODMAN_IMAGES="ghcr.io/appsinacup/gamend:latest-slim"   # pulled when missing
BUILD_ARGS=(--build-arg "SYNC=$(date +%s)")             # a layer never cached
MAKE_DIRS="backups logs"                 # default; created for bind mounts
EXPORT_FILES=0                           # --export leaves the stored files out
MIN_FREE_GB=50 DISK_PATH=.
UP_TIMEOUT=600                           # how long `up --wait` waits
KEEP_HOURS=336                           # build cache kept by the prune (or KEEP_CACHE=20GB)

app_preflight() { …; }                   # more checks: ok "…", warn "…", bad "…"
app_after_up() { …; }                    # a step once the stack is up
app_hints() { …; }                       # lines printed at the end
```

The hooks get the script's helpers: `ok`, `warn`, `bad` (a stop), `note`,
`step`, `need_env NAME…`, `want_env NAME…`, `on_machine ADDRESS`, and
`$COMPOSE`, the compose command with the app's files.

## What it does

1. **Reads `.env` as compose does**, never through the shell: a value with a
   quote, a `$` or a backtick cannot stop it or run, and a line compose would
   refuse is named.
2. **Checks the host** as `deploy.conf` asks. A failure stops before anything
   is built.
3. **Builds** with `--pull`, so a new base image is picked up, and the cache.
4. **Starts** with `up -d --remove-orphans --wait`, and prints how long the app
   did not answer. Give the app's service a healthcheck, or `--wait` only waits
   for the container to start.
5. **Prunes** build cache older than `KEEP_HOURS` and dangling images, after
   the build so its own layers survive. Never `docker system prune`.

## Backups

The database's backup is a service of the app's compose file on the
`gamend-backup` image (`../docker/backup/README.md`); nothing to copy.
