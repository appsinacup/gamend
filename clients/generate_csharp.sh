#!/usr/bin/env bash
# Write the C# SDK into csharp_sdk/, the way generate_cpp.sh writes the C++ one:
# the mix task refreshes the OpenAPI document, then clients/sdkgen turns it and
# the realtime table into the generated half and copies clients/csharp_template/
# over the top.
#
#   clients/generate_csharp.sh            # regenerate
#   clients/generate_csharp.sh --check    # fail when csharp_sdk/ is stale
#
# csharp_sdk/ is not committed. CI runs this with APP_VERSION set, which stamps
# the version into Version.cs and so into the package.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

if [ "${1:-}" != "--check" ]; then
  echo "Writing clients/godot/openapi.json from GamendWeb.ApiSpec"
  mix openapi.spec.json --spec GamendWeb.ApiSpec --filename clients/godot/openapi.json --pretty=true
fi

python3 clients/sdkgen csharp "$@"

if [ -n "${APP_VERSION:-}" ]; then
  echo "Stamping ${APP_VERSION} into the SDK"
  cat > csharp_sdk/src/Gamend/Version.cs <<VERSION
// The Gamend release this SDK was generated from. Stamped by CI; a local
// generation leaves it as it is.
namespace Gamend
{
    public static class GamendVersion
    {
        public const string Value = "${APP_VERSION}";
    }
}
VERSION
fi
