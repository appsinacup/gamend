#!/bin/sh
# Installs the Gamend server command line: `gamend`.
#
#   curl -fsSL https://raw.githubusercontent.com/appsinacup/gamend/main/rel/install.sh | sh
#
# Environment:
#   GAMEND_VERSION      release tag to install (default: server-latest)
#   GAMEND_ADAPTER      sqlite (default) or postgres; the database is chosen
#                       when the server is built, so each has its own download
#   GAMEND_INSTALL_DIR  where releases are unpacked (default: ~/.gamend)
#   GAMEND_BIN_DIR      where the `gamend` link goes (default: ~/.local/bin)
#   GAMEND_DOWNLOAD_URL where the archives are (default: the GitHub release of
#                       GAMEND_VERSION), for a mirror
#
# Supported: macOS on Apple silicon, Linux x86_64 and arm64 (glibc).
set -eu

repo="appsinacup/gamend"
version=${GAMEND_VERSION:-server-latest}
adapter=${GAMEND_ADAPTER:-sqlite}
install_dir=${GAMEND_INSTALL_DIR:-$HOME/.gamend}
bin_dir=${GAMEND_BIN_DIR:-$HOME/.local/bin}

fail() {
  echo "gamend install: $*" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *) fail "unsupported OS $(uname -s); use the Docker image instead (ghcr.io/$repo)" ;;
esac

case "$(uname -m)" in
  arm64 | aarch64) arch=arm64 ;;
  x86_64 | amd64) arch=x86_64 ;;
  *) fail "unsupported CPU $(uname -m)" ;;
esac

[ "$os-$arch" != "macos-x86_64" ] || fail "Intel Macs are not supported; use the Docker image (ghcr.io/$repo)"

case $adapter in
  sqlite) suffix="" ;;
  postgres) suffix="-postgres" ;;
  *) fail "GAMEND_ADAPTER must be sqlite or postgres, not $adapter" ;;
esac

name="gamend-$os-$arch$suffix"
base=${GAMEND_DOWNLOAD_URL:-https://github.com/$repo/releases/download/$version}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $name ($version)"
curl -fSL --progress-bar "$base/$name.tar.gz" -o "$tmp/$name.tar.gz" ||
  fail "download failed: $base/$name.tar.gz"

if curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS" 2>/dev/null; then
  expected=$(grep " $name.tar.gz\$" "$tmp/SHA256SUMS" | cut -d ' ' -f 1)
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$tmp/$name.tar.gz" | cut -d ' ' -f 1)
  else
    actual=$(shasum -a 256 "$tmp/$name.tar.gz" | cut -d ' ' -f 1)
  fi
  [ "$expected" = "$actual" ] || fail "checksum mismatch for $name.tar.gz"
fi

target="$install_dir/$version-$adapter"
rm -rf "$target"
mkdir -p "$target" "$bin_dir"
tar -xzf "$tmp/$name.tar.gz" -C "$target"
ln -sfn "$target/gamend/bin/gamend" "$bin_dir/gamend"

echo "Installed $("$bin_dir/gamend" version) to $target"

# In GitHub Actions, later steps find it on PATH.
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$bin_dir" >>"$GITHUB_PATH"
fi

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "Add $bin_dir to your PATH to run \`gamend\` from anywhere." ;;
esac

echo "Start a project: mkdir my-game && cd my-game && gamend starter && gamend start"
