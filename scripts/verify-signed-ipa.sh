#!/usr/bin/env bash
set -euo pipefail

IPA="${1:?usage: verify-signed-ipa.sh /path/to/signed.ipa}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q "$IPA" -d "$TMP"
APP=$(find "$TMP/Payload" -maxdepth 1 -name '*.app' -print -quit)
EXT="$APP/PlugIns/DatebookWidgets.appex"

"$(dirname "$0")/validate-live-activity-bundle.sh" "$APP"
codesign --verify --strict --verbose=2 "$EXT"
codesign --verify --strict --verbose=2 "$APP"

codesign -d --entitlements "$TMP/app-entitlements.plist" "$APP" 2>/dev/null
codesign -d --entitlements "$TMP/widget-entitlements.plist" "$EXT" 2>/dev/null
APP_GROUP=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$TMP/app-entitlements.plist")
EXT_GROUP=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$TMP/widget-entitlements.plist")
test "$APP_GROUP" = 'group.com.sarveshjagtap.datebook' || { echo "App Group missing from app signature"; exit 1; }
test "$EXT_GROUP" = "$APP_GROUP" || { echo "App/extension App Groups differ"; exit 1; }

echo "Signed IPA verification passed. App and widget signatures preserve $APP_GROUP."
