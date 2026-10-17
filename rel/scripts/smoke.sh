#!/usr/bin/env bash
# Boots a packaged archive the way a user would, from an empty project folder.
#
#   rel/scripts/smoke.sh dist/gamend-linux-x86_64.tar.gz
#
# Unpacks it, runs `gamend starter`, builds the starter's GDScript plugin with
# `gamend plugin.bundle` (no Mix involved), runs `gamend daemon`, waits for the
# health endpoint, renders the home page, calls the plugin as a player, seeds
# demo data against the running server, stops it, then rolls back, migrates and
# resets the database. For a Postgres build, point GAMEND_DB_URL at a database
# first.
set -euo pipefail

archive=$(cd "$(dirname "${1:?usage: smoke.sh ARCHIVE}")" && pwd -P)/$(basename "$1")
port=${GAMEND_HTTP_PORT:-4321}
work=$(mktemp -d)

cleanup() {
  (cd "$work/project" 2>/dev/null && "$work/gamend/bin/gamend" stop >/dev/null 2>&1) || true
  rm -rf "$work"
}
trap cleanup EXIT

tar -xzf "$archive" -C "$work"
gamend="$work/gamend/bin/gamend"
mkdir "$work/project"
cd "$work/project"

"$gamend" version
"$gamend" starter
echo "GAMEND_HTTP_PORT=$port" >>.env
"$gamend" plugin.bundle
"$gamend" daemon

for _ in $(seq 1 90); do
  curl -fsS "http://127.0.0.1:$port/api/v1/health" >/dev/null 2>&1 && break
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:$port/api/v1/health"; then
  echo "server never became healthy; log:" >&2
  cat .gamend/tmp/log/erlang.log.* >&2 || true
  exit 1
fi
echo

# `grep >/dev/null`, never `grep -q`, after a curl: -q exits on the first
# match and closes the pipe, so a page longer than that curl writes into a
# closed pipe, fails with 23, and pipefail fails the run.
curl -fsS "http://127.0.0.1:$port/" | grep "My Game" >/dev/null
curl -fsS -o /dev/null "http://127.0.0.1:$port/docs/getting-started"

token=$(curl -fsS -X POST "http://127.0.0.1:$port/api/v1/login/device" \
  -H 'content-type: application/json' -d '{"device_id":"smoke-test-device-0001"}' |
  grep -o '"access_token":"[^"]*"' | cut -d '"' -f 4)
curl -fsS -X POST "http://127.0.0.1:$port/api/v1/hooks/call" \
  -H "authorization: Bearer $token" -H 'content-type: application/json' \
  -d '{"plugin":"hello","fn":"hello","args":["smoke"]}' | grep "Hello, smoke!" >/dev/null
"$gamend" demo.seed --count 5 --only leaderboard
curl -fsS "http://127.0.0.1:$port/api/v1/leaderboards" | grep demo_seed >/dev/null
"$gamend" stop

# The database commands, against the stopped server's database.
"$gamend" db.rollback --step 1
"$gamend" db.migrate
"$gamend" db.reset
"$gamend" demo.seed --count 5 --only group

echo "smoke: ok"
