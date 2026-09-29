#!/usr/bin/env bash
# Builds the C libraries a downloadable release links, as static archives, into
# one prefix: OpenSSL (for OTP's :crypto and ex_dtls) and libsrtp (ex_libsrtp).
#
#   rel/scripts/static-deps.sh /opt/gamend-deps
#
# A release carries its own ERTS and NIFs; anything they link dynamically has
# to exist on the machine it lands on. OpenSSL 3 is missing from macOS and from
# older or minimal Linux installs, and libsrtp is missing almost everywhere, so
# both go inside the binaries instead. Only `.a` files are installed (no-shared),
# which is what makes `-lssl -lcrypto -lsrtp2` pick the static copy.
set -euo pipefail

prefix=${1:?usage: static-deps.sh PREFIX}
openssl_version=${OPENSSL_VERSION:-3.5.8}
libsrtp_version=${LIBSRTP_VERSION:-2.7.0}
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)

mkdir -p "$prefix"
prefix=$(cd "$prefix" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -f "$prefix/lib/libcrypto.a" ]; then
  echo "==> OpenSSL $openssl_version"
  curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz" |
    tar xz -C "$work"
  (
    cd "$work/openssl-$openssl_version"
    # --libdir=lib: x86_64 Linux would otherwise install into lib64, where
    # neither pkg-config paths below nor OTP's --with-ssl look.
    ./config no-shared no-tests no-docs -fPIC --prefix="$prefix" --libdir=lib --openssldir="$prefix/ssl"
    make -j"$jobs" >/dev/null
    make install_sw >/dev/null
  )
fi

if [ ! -f "$prefix/lib/libsrtp2.a" ]; then
  echo "==> libsrtp $libsrtp_version"
  curl -fsSL "https://github.com/cisco/libsrtp/archive/refs/tags/v$libsrtp_version.tar.gz" |
    tar xz -C "$work"
  (
    cd "$work/libsrtp-$libsrtp_version"
    CFLAGS="-fPIC -O2" ./configure --prefix="$prefix" >/dev/null
    make -j"$jobs" libsrtp2.a >/dev/null
    make install >/dev/null
  )
  # `make install` may also place a shared copy when the platform builds one;
  # only the archive may be found.
  rm -f "$prefix"/lib/libsrtp2.so* "$prefix"/lib/libsrtp2*.dylib
fi

echo "Static deps in $prefix:"
ls "$prefix/lib"
