#!/usr/bin/env bash
# Write the Unreal plugin into unreal_plugin/Gamend/: clients/unreal_template/
# with the C++ SDK's sources copied into its GamendSDK module, and
# nlohmann/json, which Unreal does not ship.
#
#   clients/generate_unreal.sh            # regenerate cpp_sdk/ first, then the plugin
#   clients/generate_unreal.sh --no-cpp   # take cpp_sdk/ as it is (CI downloads it)
#
# unreal_plugin/ is not committed. CI zips unreal_plugin/Gamend into
# gamend-unreal-plugin.zip on the `latest` release; the version stamped into
# cpp_sdk/include/gamend/version.hpp becomes the plugin's. The SDK's curl,
# IXWebSocket and libdatachannel transports stay out: the Gamend module gives
# the client Unreal's HTTP and WebSocket modules instead.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

if [ "${1:-}" != "--no-cpp" ]; then
  clients/generate_cpp.sh
fi

SDK_DIR="$ROOT_DIR/cpp_sdk"
if [ ! -f "$SDK_DIR/include/gamend/gamend.hpp" ]; then
  echo "cpp_sdk/ is missing: run clients/generate_cpp.sh first" >&2
  exit 1
fi

OUT_ROOT="$ROOT_DIR/unreal_plugin"
OUT="$OUT_ROOT/Gamend"
MODULE="$OUT/Source/GamendSDK"
rm -rf "$OUT"
mkdir -p "$OUT_ROOT"
cp -R clients/unreal_template "$OUT"

# The SDK, as it is, minus the transports Unreal replaces.
mkdir -p "$MODULE/Public" "$MODULE/Private" "$MODULE/ThirdParty/nlohmann"
cp -R "$SDK_DIR/include/gamend" "$MODULE/Public/"
for transport in curl_transport ix_websocket_transport libdatachannel_transport; do
  rm -f "$MODULE/Public/gamend/$transport.hpp"
done
for source in "$SDK_DIR"/src/*.cpp "$SDK_DIR"/src/*.hpp; do
  case "$(basename "$source")" in
    curl_transport.cpp | ix_websocket_transport.cpp | libdatachannel_transport.cpp) ;;
    *) cp "$source" "$MODULE/Private/" ;;
  esac
done
cp "$SDK_DIR/LICENSE" "$OUT/LICENSE"
cp "$SDK_DIR/REFERENCE.md" "$OUT/REFERENCE.md"

# nlohmann/json, the release the SDK's CMakeLists.txt pins, downloaded once
# into unreal_plugin/.cache.
json_pin=$(sed -n '/FetchContent_Declare(nlohmann_json/,/URL_HASH/p' "$SDK_DIR/CMakeLists.txt")
json_url=$(echo "$json_pin" | sed -n 's|^ *URL \(https://[^ ]*\)$|\1|p')
json_sha=$(echo "$json_pin" | sed -n 's|^ *URL_HASH SHA256=\([0-9a-f]\{64\}\))*$|\1|p')
if [ -z "$json_url" ] || [ -z "$json_sha" ]; then
  echo "could not read the nlohmann/json pin from cpp_sdk/CMakeLists.txt" >&2
  exit 1
fi
CACHE="$OUT_ROOT/.cache"
archive="$CACHE/nlohmann-json-$json_sha.tar.xz"
mkdir -p "$CACHE"
sha256() {
  if command -v sha256sum > /dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
if [ ! -f "$archive" ] || [ "$(sha256 "$archive")" != "$json_sha" ]; then
  echo "Downloading $json_url"
  curl -fsSL --retry 5 -o "$archive.part" "$json_url"
  if [ "$(sha256 "$archive.part")" != "$json_sha" ]; then
    rm -f "$archive.part"
    echo "$json_url does not match its SHA256 in cpp_sdk/CMakeLists.txt" >&2
    exit 1
  fi
  mv "$archive.part" "$archive"
fi
unpacked="$CACHE/nlohmann-json"
rm -rf "$unpacked"
mkdir -p "$unpacked"
tar -xJf "$archive" -C "$unpacked" json/single_include/nlohmann/json.hpp json/LICENSE.MIT
cp "$unpacked/json/single_include/nlohmann/json.hpp" "$MODULE/ThirdParty/nlohmann/json.hpp"
cp "$unpacked/json/LICENSE.MIT" "$MODULE/ThirdParty/nlohmann/LICENSE.MIT"
rm -rf "$unpacked"

# The version: CI stamps x.y.<commits> into version.hpp. The descriptor's
# integer Version must grow from one release to the next, so it is the
# commit count; a local generation stays at 1, "dev".
version=$(sed -n 's|^#define GAMEND_VERSION "\(.*\)"$|\1|p' "$SDK_DIR/include/gamend/version.hpp")
if [[ "$version" =~ ^[0-9]+\.[0-9]+\.([0-9]+)$ ]]; then
  echo "Stamping ${version} into Gamend.uplugin"
  VERSION="$version" COUNT="${BASH_REMATCH[1]}" DESCRIPTOR="$OUT/Gamend.uplugin" python3 - <<'PY'
import json
import os

path = os.environ["DESCRIPTOR"]
with open(path) as f:
    descriptor = json.load(f)
descriptor["Version"] = int(os.environ["COUNT"])
descriptor["VersionName"] = os.environ["VERSION"]
with open(path, "w") as f:
    json.dump(descriptor, f, indent="\t")
    f.write("\n")
PY
fi

echo "Wrote the Unreal plugin (${version:-dev}) to unreal_plugin/Gamend"
