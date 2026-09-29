#!/usr/bin/env bash
# Turns the release `mix release` built into the downloadable archive.
#
#   rel/scripts/package.sh gamend-linux-x86_64 dist/
#
# Writes dist/<name>.tar.gz holding one directory, gamend/, with the command
# line at gamend/bin/gamend. On the way it:
#   * drops the gamend.org website from the engine (the demo game, the site's
#     pictures, robots.txt and llms.txt, plus their cache manifest entries):
#     those ship as gamend-website.tar.gz, and a project brings its own;
#   * refuses a binary that links a library the target machine may not have
#     (OpenSSL, libsrtp, SQLite, anything from Homebrew or /usr/local);
#   * signs and notarizes every Mach-O file when APPLE_SIGNING_IDENTITY is set
#     (rel/scripts/sign-macos.sh).
set -euo pipefail

name=${1:?usage: package.sh NAME OUT_DIR}
out=${2:?usage: package.sh NAME OUT_DIR}
root=$(cd "$(dirname "$0")/../.." && pwd -P)
release="$root/_build/prod/rel/gamend_host"

[ -x "$release/bin/gamend" ] || {
  echo "no release at $release: run MIX_ENV=prod mix release first" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stage="$work/gamend"
cp -R "$release" "$stage"

# ── The website out ──────────────────────────────────────────────────────────
static=$(echo "$stage"/lib/gamend_host-*/priv/static)
priv=$(dirname "$static")
rm -rf "$static/game" "$static/images" "$priv/image_backups" "$priv/storage"
rm -f "$static"/llms*.txt* "$static"/robots*.txt*

manifest="$static/cache_manifest.json"
if [ -f "$manifest" ]; then
  site='^(images/|game/|llms|robots)'
  jq --arg site "$site" '
    .latest |= with_entries(select(.key | test($site) | not))
    | .digests |= with_entries(select(.value.logical_path | test($site) | not))
  ' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
  rm -f "$manifest".gz "$manifest".br "$manifest"-*
fi

# ── Linkage check ────────────────────────────────────────────────────────────
forbidden='ssl|crypto|srtp|sqlite|homebrew|/usr/local/|/opt/'
failed=0
while IFS= read -r file; do
  case $(uname -s) in
    Darwin)
      file "$file" | grep -q 'Mach-O' || continue
      # A shared library lists its own install name first; that is not a
      # dependency (a prebuilt NIF's names its CI machine's build path).
      id=$(otool -D "$file" | tail -n +2)
      deps=$(otool -L "$file" | tail -n +2 | awk '{print $1}' | grep -vxF "${id:-/}" || true)
      ;;
    *)
      file "$file" | grep -q 'ELF' || continue
      deps=$(readelf -d "$file" 2>/dev/null | awk -F'[][]' '/NEEDED/ {print $2}')
      ;;
  esac
  bad=$(printf '%s\n' "$deps" | grep -E "$forbidden" || true)
  if [ -n "$bad" ]; then
    echo "error: ${file#"$stage"/} links $(echo "$bad" | tr '\n' ' ')" >&2
    failed=1
  fi
done < <(find "$stage" -type f \( -perm -u+x -o -name '*.so' -o -name '*.dylib' \))
[ "$failed" = 0 ] || exit 1

if [ "$(uname -s)" = "Linux" ]; then
  # The oldest glibc a machine needs: the highest symbol version referenced.
  glibc=$(find "$stage" -type f \( -name '*.so' -o -perm -u+x \) -exec sh -c \
    'file "$1" | grep -q ELF && objdump -T "$1" 2>/dev/null' _ {} \; |
    grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)
  echo "Needs ${glibc:-GLIBC_?} or newer"
fi

# ── Sign (macOS) ─────────────────────────────────────────────────────────────
if [ "$(uname -s)" = "Darwin" ] && [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
  "$root/rel/scripts/sign-macos.sh" "$stage"
fi

mkdir -p "$out"
tar -czf "$out/$name.tar.gz" -C "$work" gamend
echo "Wrote $out/$name.tar.gz ($(du -h "$out/$name.tar.gz" | cut -f1))"
