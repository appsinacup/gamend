#!/usr/bin/env bash
# Packs the gamend.org website as a project folder, for `gamend starter website`.
#
#   rel/scripts/website.sh dist/
#
# Writes dist/gamend-website.tar.gz: the theme, the markdown content and the
# site's static files, laid out the way a release reads a project (the static
# files under static/). Only files tracked in git go in, so generated digests
# and compressed copies stay out.
set -euo pipefail

out=${1:?usage: website.sh OUT_DIR}
root=$(cd "$(dirname "$0")/../.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
site="$work/gamend-website"
mkdir -p "$site/static"

cd "$root"

copy() {
  git ls-files -z -- "$1" | while IFS= read -r -d '' file; do
    target="$site/${2:-}${file#"${3:-}"}"
    mkdir -p "$(dirname "$target")"
    cp "$file" "$target"
  done
}

copy theme
copy CHANGELOG.md
copy ROADMAP.md
copy blog
copy priv/docs
copy .env.example

# priv/static/<entry> → static/<entry>, for the entries the engine lets a
# project serve (host_static_paths in config/host_config.exs).
for entry in images game favicon.ico robots.txt llms.txt .well-known theme.css; do
  copy "priv/static/$entry" "static/" "priv/static/"
done

mkdir -p "$out"
tar -czf "$out/gamend-website.tar.gz" -C "$work" gamend-website
echo "Wrote $out/gamend-website.tar.gz ($(du -h "$out/gamend-website.tar.gz" | cut -f1))"
