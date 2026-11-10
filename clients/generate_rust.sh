#!/usr/bin/env bash
# Write the Rust SDK into rust_sdk/, the way generate_csharp.sh writes the C# one:
# the mix task refreshes the OpenAPI document, then clients/sdkgen turns it and
# the realtime table into the generated half and copies clients/rust_template/
# over the top.
#
#   clients/generate_rust.sh            # regenerate
#   clients/generate_rust.sh --check    # fail when rust_sdk/ is stale
#
# rust_sdk/ is not committed. CI runs this with APP_VERSION set, which stamps the
# version into Cargo.toml and so into the crate and its user agent.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

if [ "${1:-}" != "--check" ]; then
  echo "Writing clients/godot/openapi.json from GamendWeb.ApiSpec"
  mix openapi.spec.json --spec GamendWeb.ApiSpec --filename clients/godot/openapi.json --pretty=true
fi

python3 clients/sdkgen rust "$@"

if [ -n "${APP_VERSION:-}" ]; then
  echo "Stamping ${APP_VERSION} into the SDK"
  # Anchored: dependencies carry their versions inline, and only the package's
  # own sits at the start of a line.
  sed -i.bak "s/^version = \".*\"/version = \"${APP_VERSION}\"/" rust_sdk/Cargo.toml
  rm rust_sdk/Cargo.toml.bak
fi
