#!/bin/bash
# Toolchain for Claude Code cloud sessions on this repo.
#
# Paste this file into the cloud environment's Setup script field (the
# environment menu in a session's title bar, then Edit). The setup script runs
# before Claude starts, and when it finishes within about five minutes the
# filesystem is snapshotted and every later session starts from that snapshot,
# with all of this already installed. It re-runs only when the script or the
# network settings change, or after about seven days. This takes 1-2 minutes.
#
# It installs what the base image (Ubuntu 24.04, with Rust, gcc and cmake)
# lacks:
#   - Erlang/OTP and Elixir, prebuilt by hex.pm (builds.hex.pm, the builds
#     setup-beam uses in CI), linked into /usr/local/bin
#   - libsrtp2 (ex_webrtc) and inotify-tools (live reload in dev)
#   - hex and rebar
#
# The versions are the ones CI builds with (ELIXIR_VERSION and OTP_VERSION in
# .github/workflows/build-and-check.yml): a newer Elixir patch brings new type
# warnings, which `mix precommit` compiles as errors. The repo's SessionStart
# hook (.claude/hooks/session-start.sh) runs this same file with CI's current
# pins, so a stale copy here costs time, not correctness. Idempotent: each step
# skips when its result is present.
set -Eeuo pipefail

# A setup script that exits non-zero stops the session from starting at all,
# so report and carry on: the SessionStart hook installs whatever is missing.
# The hook runs this with GAMEND_SETUP_STRICT=1 to see failures.
if [ "${GAMEND_SETUP_STRICT:-0}" != "1" ]; then
  trap 'echo "cloud-setup: failed at line $LINENO; the SessionStart hook will retry" >&2; exit 0' ERR
fi

OTP_VERSION="${OTP_VERSION:-29.1.1}"
# A series ("1.20") would take its newest patch built for this OTP major.
ELIXIR_VERSION="${ELIXIR_VERSION:-1.20.4}"

# Elixir warns under the image's default POSIX locale (latin1 file names).
export LANG=C.UTF-8 LC_ALL=C.UTF-8

tools=/opt/gamend-tools
otp_major=${OTP_VERSION%%.*}
otp_dir="$tools/otp-$OTP_VERSION"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ ! -x "$otp_dir/bin/erl" ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  echo "Installing Erlang/OTP $OTP_VERSION"
  curl -fsSL "https://builds.hex.pm/builds/otp/${ID}-${VERSION_ID}/OTP-${OTP_VERSION}.tar.gz" -o "$tmp/otp.tar.gz"
  mkdir -p "$otp_dir"
  tar -xzf "$tmp/otp.tar.gz" -C "$otp_dir" --strip-components=1
  "$otp_dir/Install" -minimal "$otp_dir" > /dev/null
fi

# A matching build already installed wins, so a warm environment needs no
# network here.
elixir_re="^v${ELIXIR_VERSION//./\\.}(\\.[0-9]+)?-otp-${otp_major}\$"
elixir_build=$(find "$tools" -maxdepth 1 -name 'elixir-*' -printf '%f\n' 2> /dev/null | sed 's/^elixir-//' | grep -E "$elixir_re" | sort -V | tail -n 1 || true)
if [ -z "$elixir_build" ]; then
  elixir_build=$(curl -fsSL https://builds.hex.pm/builds/elixir/builds.txt |
    awk '{print $1}' | grep -E "$elixir_re" | sort -V | tail -n 1 || true)
fi
if [ -z "$elixir_build" ]; then
  echo "No Elixir build matches $ELIXIR_VERSION for OTP $otp_major" >&2
  false
fi
elixir_dir="$tools/elixir-$elixir_build"

if [ ! -x "$elixir_dir/bin/elixir" ]; then
  echo "Installing Elixir $elixir_build"
  curl -fsSL "https://builds.hex.pm/builds/elixir/${elixir_build}.zip" -o "$tmp/elixir.zip"
  mkdir -p "$elixir_dir"
  unzip -q -o "$tmp/elixir.zip" -d "$elixir_dir"
fi

# On PATH for every process, including the preview launcher in
# .claude/launch.json, which runs `mix` without a login shell.
for bin in erl erlc escript; do ln -sf "$otp_dir/bin/$bin" /usr/local/bin/$bin; done
for bin in elixir elixirc iex mix; do ln -sf "$elixir_dir/bin/$bin" /usr/local/bin/$bin; done

if ! pkg-config --exists libsrtp2 2> /dev/null || ! command -v inotifywait > /dev/null; then
  echo "Installing libsrtp2-dev and inotify-tools"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libsrtp2-dev inotify-tools > /dev/null
fi

# Outside any project: inside one, Mix loads its mix.exs first and fails on
# the deps it cannot fetch without hex.
(cd /tmp && mix local.hex --force --if-missing > /dev/null && mix local.rebar --force --if-missing > /dev/null)

echo "Erlang/OTP $OTP_VERSION and Elixir ${elixir_build#v} ready"
