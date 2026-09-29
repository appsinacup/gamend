#!/usr/bin/env bash
# Signs every Mach-O file of a staged release with a Developer ID, then
# notarizes it, so Gatekeeper lets a downloaded copy run.
#
#   APPLE_SIGNING_IDENTITY="Developer ID Application: …" \
#   APPLE_ID=… APPLE_APP_SPECIFIC_PASSWORD=… APPLE_TEAM_ID=… \
#   rel/scripts/sign-macos.sh path/to/gamend
#
# The signing identity has to be in a keychain already (the workflow imports
# it). Notarizing is skipped when the Apple ID variables are unset. A folder
# of binaries cannot be stapled, so Gatekeeper checks the ticket online the
# first time each binary runs.
set -euo pipefail

stage=${1:?usage: sign-macos.sh STAGE_DIR}
identity=${APPLE_SIGNING_IDENTITY:?APPLE_SIGNING_IDENTITY is not set}
here=$(cd "$(dirname "$0")" && pwd -P)

# The BEAM's JIT writes machine code at run time, which the hardened runtime
# only allows with this entitlement.
entitlements="$here/entitlements.plist"

count=0
while IFS= read -r file; do
  file "$file" | grep -q 'Mach-O' || continue
  codesign --force --timestamp --options runtime \
    --entitlements "$entitlements" --sign "$identity" "$file"
  count=$((count + 1))
done < <(find "$stage" -type f)
echo "Signed $count Mach-O files"

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  zip=$(mktemp -d)/gamend.zip
  ditto -c -k --keepParent "$stage" "$zip"
  xcrun notarytool submit "$zip" \
    --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" \
    --wait --timeout 30m
  rm -f "$zip"
else
  echo "APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD or APPLE_TEAM_ID unset: signed, not notarized"
fi
