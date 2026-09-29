#!/usr/bin/env bash
# Builds the release a download ships, from a clean checkout, the way CI does.
#
#   GAMEND_DB_ADAPTER=sqlite rel/scripts/build.sh ~/gamend-build
#
# Into the build root it puts (or reuses) the static OpenSSL and libsrtp, an
# OTP built against them, Elixir and Rust, then runs `mix release` with
# MIX_ENV=prod. Package the result with rel/scripts/package.sh.
set -euo pipefail

build_root=${1:?usage: build.sh BUILD_ROOT}
mkdir -p "$build_root"
build_root=$(cd "$build_root" && pwd -P)
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)

otp_version=${OTP_VERSION:-29.0.2}
elixir_version=${ELIXIR_VERSION:-1.20.1}

"$here/static-deps.sh" "$build_root/deps"
OTP_VERSION=$otp_version "$here/build-otp.sh" "$build_root/otp" "$build_root/deps"

if [ ! -x "$build_root/elixir/bin/elixir" ]; then
  curl -fsSL "https://github.com/elixir-lang/elixir/releases/download/v$elixir_version/elixir-otp-${otp_version%%.*}.zip" \
    -o "$build_root/elixir.zip"
  mkdir -p "$build_root/elixir"
  unzip -q -o "$build_root/elixir.zip" -d "$build_root/elixir"
fi

if ! command -v cargo >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
fi

export PATH="$build_root/otp/bin:$build_root/elixir/bin:$HOME/.cargo/bin:$PATH"
export MIX_ENV=prod
export LANG=${LANG:-C.UTF-8}
# Link ex_dtls and ex_libsrtp against the static libraries (config/host_config.exs).
export GAMEND_BUILD_STATIC_DEPS=true
export PKG_CONFIG_PATH="$build_root/deps/lib/pkgconfig"

# Outside the project: inside it, Mix loads mix.exs first and fails on the
# Hex dependencies it cannot resolve yet.
(cd "$build_root" && mix local.hex --force --if-missing && mix local.rebar --force --if-missing)

cd "$repo"
mix deps.get --only prod
mix compile
mix assets.deploy
mix release --overwrite
