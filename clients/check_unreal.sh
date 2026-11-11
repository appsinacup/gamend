#!/usr/bin/env bash
# Build the Unreal plugin's GamendSDK module the way an editor build links it,
# without Unreal: CI cannot run the engine, so this is the part of the plugin
# it can hold to account.
#
#   clients/generate_unreal.sh --no-cpp && clients/check_unreal.sh
#
# For C++17 (Unreal 5.0 to 5.2) and C++20 (5.3 on), with the engine's own
# rules (no exceptions, no RTTI, -Wshadow and -Wundef as errors), it
#
#   1. compiles every public header on its own, as a game's include would;
#   2. builds the module's sources into a shared library whose symbols are
#      hidden unless GAMEND_EXPORT marks them, as an editor build's module is;
#   3. links clients/unreal_check/sdk_check.cpp against it and runs it.
#
# The Gamend module (the subsystem, the Unreal transports and the Blueprint
# nodes) needs the engine's headers, and is not built here.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

PLUGIN="${1:-$ROOT_DIR/unreal_plugin/Gamend}"
MODULE="$PLUGIN/Source/GamendSDK"
if [ ! -f "$MODULE/Public/gamend/gamend.hpp" ]; then
  echo "$MODULE has no SDK: run clients/generate_unreal.sh first" >&2
  exit 1
fi

CXX="${CXX:-$(command -v clang++ || command -v c++)}"
JOBS="$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)"
BUILD="$ROOT_DIR/tmp/check_unreal"
rm -rf "$BUILD"
mkdir -p "$BUILD"

case "$(uname -s)" in
  Darwin) shared=(-dynamiclib -install_name @rpath/libgamend_sdk.dylib) && library=libgamend_sdk.dylib ;;
  *) shared=(-shared) && library=libgamend_sdk.so ;;
esac

FLAGS=(-fno-exceptions -fno-rtti -Wall -Wextra -Wpedantic -Wshadow -Wundef
  -Wdelete-non-virtual-dtor -Werror
  -I "$MODULE/Public" -isystem "$MODULE/ThirdParty")

sources=()
for source in "$MODULE"/Private/*.cpp; do
  # The module's IMPLEMENT_MODULE, the one file that includes the engine.
  [ "$(basename "$source")" = GamendSDKModule.cpp ] || sources+=("$source")
done

for std in c++17 c++20; do
  out="$BUILD/$std"
  mkdir -p "$out/obj" "$out/headers"
  echo "== $std: $CXX"

  for header in "$MODULE"/Public/gamend/*.hpp "$MODULE"/Public/gamend/testing/*.hpp; do
    name="${header#"$MODULE/Public/"}"
    printf '#include "%s"\n' "$name" > "$out/headers/$(echo "$name" | tr '/' '_').cpp"
  done
  printf '%s\0' "$out"/headers/*.cpp |
    xargs -0 -P "$JOBS" -I{} "$CXX" -std="$std" "${FLAGS[@]}" -DGAMEND_SHARED=1 -fsyntax-only {}
  echo "   every public header compiles on its own"

  printf '%s\0' "${sources[@]}" |
    xargs -0 -P "$JOBS" -I{} sh -c '
      out="$1"; shift; source="$1"; shift
      exec "$@" -c "$source" -o "$out/obj/$(basename "$source" .cpp).o"
    ' _ "$out" {} "$CXX" -std="$std" "${FLAGS[@]}" -I "$MODULE/Private" \
      -fPIC -fvisibility=hidden -DGAMEND_BUILDING=1
  "$CXX" "${shared[@]}" -o "$out/$library" "$out"/obj/*.o
  echo "   $library: ${#sources[@]} sources, symbols hidden unless exported"

  "$CXX" -std="$std" "${FLAGS[@]}" -fvisibility=hidden -DGAMEND_SHARED=1 \
    clients/unreal_check/sdk_check.cpp -o "$out/sdk_check" \
    -L "$out" -lgamend_sdk -Wl,-rpath,"$out"
  "$out/sdk_check"
done
