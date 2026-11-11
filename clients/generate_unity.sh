#!/usr/bin/env bash
# Write the Unity package into unity_sdk/: clients/unity_template/ with the C#
# SDK's sources (csharp_sdk/src/Gamend) copied into Runtime/Sdk, a .meta for
# every asset, and the SDK's version in package.json.
#
#   clients/generate_unity.sh          # write unity_sdk/
#   clients/generate_unity.sh --pack   # ...and gamend-unity-sdk.tgz, the tarball
#                                      # Unity's "Add package from tarball" reads
#
# It writes csharp_sdk/ first when there is none (clients/generate_csharp.sh).
# CI hands it the one it built, which carries the stamped version; a local
# generation is 0.0.0-dev. unity_sdk/ is not committed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

SDK=csharp_sdk/src/Gamend
OUT=unity_sdk

if [ ! -d "$SDK" ]; then
  clients/generate_csharp.sh
fi

rm -rf "$OUT"
cp -R clients/unity_template "$OUT"

# The SDK without its project file, its test fakes, and HttpClientTransport:
# Unity's HTTP is UnityWebRequest, which WebGL needs and every other platform
# takes, and System.Net.Http is not referenced under every API level.
(cd "$SDK" && find . -name '*.cs' ! -path './Testing/*' ! -path './obj/*' ! -path './bin/*' \
  ! -name HttpClientTransport.cs) | while read -r file; do
  mkdir -p "$OUT/Runtime/Sdk/$(dirname "$file")"
  cp "$SDK/$file" "$OUT/Runtime/Sdk/$file"
done
cp clients/csharp_template/LICENSE "$OUT/LICENSE.md"

VERSION=$(sed -n 's/.*Value = "\(.*\)";.*/\1/p' "$SDK/Version.cs")
if [ -z "$VERSION" ] || [ "$VERSION" = "dev" ]; then
  VERSION=0.0.0-dev
fi
python3 clients/unity_package.py "$OUT" --version "$VERSION"
echo "Wrote $OUT (org.gamend.sdk $VERSION)"

if [ "${1:-}" = "--pack" ]; then
  # npm's layout, which Unity's tarball install expects: everything under package/.
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  cp -R "$OUT" "$STAGE/package"
  # COPYFILE_DISABLE: no macOS ._ files in it.
  COPYFILE_DISABLE=1 tar -czf gamend-unity-sdk.tgz -C "$STAGE" package
  echo "Wrote gamend-unity-sdk.tgz"
fi
