#!/usr/bin/env bash
# Generate every SDK and build and test them all, the way CI does, for whichever
# this machine has the tools for.
#
#   clients/check_sdks.sh                         # build and unit tests
#   clients/check_sdks.sh http://localhost:4000   # ...and live conformance
#
# clients/godot/openapi.json must be current: any generate_*.sh writes it, as
# does `mix precommit`. A server for the live run needs the example plugins
# (GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples), and GAMEND_ADMIN_EMAIL
# and GAMEND_ADMIN_PASSWORD set here for the key-value step. Use the host the
# server is configured for: the C++ socket sends an Origin.
#
# The builds run at once. The live runs go one after another: each step waits
# ten seconds for its answer, and several SDKs at once on one busy server miss
# that for no fault of their own. Each SDK writes tmp/check_sdks/<sdk>.log.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

URL="${1:-}"
LOGS="$ROOT_DIR/tmp/check_sdks"
rm -rf "$LOGS"
mkdir -p "$LOGS"

CARGO="cargo"
if command -v rustup >/dev/null 2>&1; then
  CARGO="cargo +stable"
fi

python3 clients/sdkgen lint || exit 1
for target in cpp csharp rust; do
  python3 clients/sdkgen "$target" > /dev/null || exit 1
done

build_cpp() {
  cmake -S cpp_sdk -B cpp_sdk/build -DGAMEND_WARNINGS_AS_ERRORS=ON &&
    cmake --build cpp_sdk/build --parallel &&
    ctest --test-dir cpp_sdk/build --output-on-failure
}

live_cpp() {
  cpp_sdk/build/gamend_conformance "$URL" &&
    cpp_sdk/build/gamend_conformance "$URL" --protobuf
}

build_csharp() {
  dotnet build -warnaserror csharp_sdk && dotnet test --no-build csharp_sdk
}

live_csharp() {
  dotnet run --no-build --project csharp_sdk/examples/Conformance -- "$URL" &&
    dotnet run --no-build --project csharp_sdk/examples/Conformance -- "$URL" --protobuf
}

build_rust() {
  cd rust_sdk &&
    $CARGO fmt --check &&
    $CARGO clippy --all-targets -- -D warnings &&
    $CARGO test &&
    $CARGO check --no-default-features --target wasm32-unknown-unknown &&
    $CARGO build --example conformance
}

live_rust() {
  cd rust_sdk &&
    $CARGO run --example conformance -- "$URL" &&
    $CARGO run --example conformance -- "$URL" --protobuf
}

build_typescript() {
  python3 clients/sdkgen ts --spec clients/godot/openapi.json &&
    cd clients && npm run check:types
}

build_godot() {
  clients/check_godot.sh
}

live_godot() {
  clients/check_godot.sh "$URL"
}

# The tool an SDK needs, and the file that says it has been generated.
needs() {
  case "$1" in
    cpp) command -v cmake ;;
    csharp) command -v dotnet ;;
    rust) command -v cargo ;;
    typescript) command -v npx && test -f clients/javascript/dist/index.js ;;
    godot) test -d godot_addons/addons/gamend ;;
  esac
}

names=()
pids=()
for sdk in cpp csharp rust typescript godot; do
  if ! needs "$sdk" > /dev/null 2>&1; then
    echo "skip $sdk: its tool or generated output is not here"
    continue
  fi
  ("build_$sdk") > "$LOGS/$sdk.log" 2>&1 &
  names+=("$sdk")
  pids+=("$!")
done

failed=0
built=()
for i in "${!names[@]}"; do
  if wait "${pids[$i]}"; then
    echo "ok   ${names[$i]} build and tests"
    built+=("${names[$i]}")
  else
    echo "FAIL ${names[$i]} build and tests (see tmp/check_sdks/${names[$i]}.log)"
    failed=1
  fi
done

if [ -n "$URL" ]; then
  for sdk in "${built[@]}"; do
    declare -F "live_$sdk" > /dev/null || continue
    if ("live_$sdk") >> "$LOGS/$sdk.log" 2>&1; then
      echo "ok   $sdk live"
    else
      echo "FAIL $sdk live (see tmp/check_sdks/$sdk.log)"
      failed=1
    fi
  done
fi
exit "$failed"
