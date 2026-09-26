#!/bin/bash
# SessionStart hook for Claude Code cloud sessions: fetch and compile the Mix
# deps, so `mix test`, `mix precommit` and `mix dev.start` work from the first
# prompt. Local sessions skip it.
#
# The toolchain (Erlang/OTP, Elixir, libsrtp2, hex) belongs in the cloud
# environment's setup script, which is snapshotted so new sessions start with
# it installed: paste .claude/cloud-setup.sh there. This runs that same file
# first, with the versions CI builds with; with the snapshot in place it finds
# everything installed and takes a second, and without it (or after CI moves to
# a new version) it installs what is missing.
#
# Everything here is idempotent. A resumed session pays for a no-op compile; a
# fresh VM compiles the deps, which takes several minutes.
#
# Output goes to $LOG, not stdout: a SessionStart hook's stdout is added to the
# session's context, and a dependency compile is thousands of lines.
set -Eeuo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

LOG=/tmp/gamend-session-start.log
: > "$LOG"
step="start"
trap 'echo "session-start: failed during \"$step\" (exit $?); see $LOG"; tail -n 20 "$LOG"' ERR

run() {
  step="$1"
  shift
  echo "== $step ($(date +%T))" >> "$LOG"
  "$@" >> "$LOG" 2>&1
}

cd "$CLAUDE_PROJECT_DIR"

# Elixir reads file names and arguments in the VM's native encoding, which is
# latin1 under the image's default POSIX locale.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export LANG=C.UTF-8 LC_ALL=C.UTF-8" >> "$CLAUDE_ENV_FILE"
fi

# CI's pins, so what passes here passes there; .tool-versions if the workflow
# stops declaring them.
ci=.github/workflows/build-and-check.yml
otp_version=$(awk -F'"' '/^  OTP_VERSION:/ {print $2; exit}' "$ci" 2> /dev/null || true)
elixir_version=$(awk -F'"' '/^  ELIXIR_VERSION:/ {print $2; exit}' "$ci" 2> /dev/null || true)
otp_version=${otp_version:-$(awk '$1 == "erlang" {print $2}' .tool-versions)}
elixir_version=${elixir_version:-$(awk '$1 == "elixir" {print $2}' .tool-versions)}

run "toolchain (Erlang/OTP $otp_version, Elixir $elixir_version)" \
  env GAMEND_SETUP_STRICT=1 OTP_VERSION="$otp_version" ELIXIR_VERSION="$elixir_version" \
  bash .claude/cloud-setup.sh

# apps/gamend_core and apps/gamend_web are Mix projects of their own, with
# their own lockfile and deps/, and root `mix test` runs their suites in place.
run "mix deps.get" mix deps.get
run "mix deps.get (apps/gamend_core)" sh -c 'cd apps/gamend_core && mix deps.get'
run "mix deps.get (apps/gamend_web)" sh -c 'cd apps/gamend_web && mix deps.get'

run "mix compile (dev)" mix compile
run "mix compile (test)" env MIX_ENV=test mix compile

# The JS SDK checks in clients/ (check_realtime.mjs and friends).
run "npm install (clients)" sh -c 'cd clients && npm install --no-audit --no-fund'

echo "session-start: $(elixir --short-version 2> /dev/null | tail -n 1) on OTP $otp_version; deps fetched and compiled (log: $LOG)"
