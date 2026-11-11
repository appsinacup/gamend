#!/usr/bin/env bash
# Check the Unity package (unity_sdk/, written by generate_unity.sh) where
# there is no Unity:
#
#   clients/check_unity.sh
#
# - every asset has a .meta, and no two share a GUID (unity_package.py);
# - the Gamend assembly compiles as Unity compiles it (C# 9, no UnityEngine),
#   and Gamend.Unity and the sample compile against UnityEngine stubs, for the
#   editor and the other players and again for WebGL (clients/unity_check);
# - GamendWebSocket.jslib, run in node against a fake WebSocket and heap,
#   hands C# what the C# side reads (unity_check/test_jslib.js).
#
# Needs dotnet and node. It does not show the package imports in the editor,
# that an IL2CPP or WebGL player builds, or that it reaches a server: only
# Unity can, which CI does not have.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR"

if [ ! -d unity_sdk ]; then
  echo "error: unity_sdk/ is missing; run clients/generate_unity.sh first" >&2
  exit 2
fi

python3 clients/unity_package.py clients/unity_template --check
python3 clients/unity_package.py unity_sdk --check
dotnet build clients/unity_check/Unity/Unity.csproj -nologo -v q
dotnet build clients/unity_check/Unity/Unity.csproj -nologo -v q -p:UnityWebGL=true
node clients/unity_check/test_jslib.js unity_sdk
echo "unity_sdk: ok"
