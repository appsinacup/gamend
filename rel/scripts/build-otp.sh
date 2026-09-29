#!/usr/bin/env bash
# Builds Erlang/OTP from source with OpenSSL linked in statically, for the ERTS
# a downloadable release ships.
#
#   rel/scripts/build-otp.sh /opt/otp /opt/gamend-deps
#
# The OTP a package manager installs links libcrypto dynamically (Homebrew's
# points at /opt/homebrew/opt/openssl@3), and a release copies that ERTS as is,
# so :crypto and :ssl would fail to load on any machine without the same
# library at the same path. The second argument is the prefix
# static-deps.sh filled.
set -euo pipefail

prefix=${1:?usage: build-otp.sh PREFIX DEPS_PREFIX}
deps=${2:?usage: build-otp.sh PREFIX DEPS_PREFIX}
otp_version=${OTP_VERSION:-29.1.1}
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)

if [ -x "$prefix/bin/erl" ]; then
  echo "OTP already built in $prefix"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -fsSL "https://github.com/erlang/otp/releases/download/OTP-$otp_version/otp_src_$otp_version.tar.gz" |
  tar xz -C "$work"

cd "$work/otp_src_$otp_version"

# Linux: carry libstdc++ (the JIT is C++) inside beam.smp too, so the only
# shared libraries left are the ones every glibc system has.
extra_ldflags=""
if [ "$(uname -s)" = "Linux" ]; then
  extra_ldflags="-static-libstdc++ -static-libgcc"
fi

LDFLAGS="${LDFLAGS:-} $extra_ldflags" ./configure \
  --prefix="$prefix" \
  --with-ssl="$deps" \
  --disable-dynamic-ssl-lib \
  --enable-builtin-zlib \
  --without-javac \
  --without-wx \
  --without-odbc \
  --without-debugger \
  --without-observer \
  --without-et

make -j"$jobs"
make install

"$prefix/bin/erl" -noshell -eval '
  {ok, _} = application:ensure_all_started(crypto),
  io:format("OTP ~s, ~s~n", [erlang:system_info(otp_release), element(3, hd(crypto:info_lib()))]),
  halt().'
