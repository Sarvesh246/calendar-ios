#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$PWD}"
PBXPROJ=$(find "$ROOT/ios" -name project.pbxproj -print -quit)
APP_ENTITLEMENTS=$(find "$ROOT/ios" -path '*/Datebook*.entitlements' ! -path '*/.targets/*' -print -quit)
EXT_ENTITLEMENTS="$ROOT/ios/.targets/DatebookWidgets/generated.entitlements"
SHARED_SOURCE="$ROOT/targets/widget/_shared/DatebookLiveSupport.swift"

test -f "$PBXPROJ" || { echo "Missing generated Xcode project"; exit 1; }
test -f "$SHARED_SOURCE" || { echo "Missing shared ActivityKit source"; exit 1; }
test -f "$APP_ENTITLEMENTS" || { echo "Missing app entitlements before archive"; exit 1; }
test -f "$EXT_ENTITLEMENTS" || { echo "Missing widget entitlements before archive"; exit 1; }

DEFINITION_COUNT=$(grep -R --include='*.swift' -l 'struct DatebookLiveAttributes: ActivityAttributes' \
  "$ROOT/modules" "$ROOT/targets" | wc -l | tr -d ' ')
test "$DEFINITION_COUNT" = "1" || {
  echo "Expected one shared DatebookLiveAttributes definition, found $DEFINITION_COUNT"
  exit 1
}

grep -q 'DatebookWidgets' "$PBXPROJ" || { echo "Widget target missing from project"; exit 1; }
grep -q '_shared' "$PBXPROJ" || { echo "Shared source group missing from project"; exit 1; }
grep -q 'DatebookLiveActivity()' "$ROOT/targets/widget/DatebookWidgets.swift" || {
  echo "DatebookLiveActivity is not registered in the widget bundle"
  exit 1
}

/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$APP_ENTITLEMENTS" \
  | grep -qx 'group.com.sarveshjagtap.datebook'
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$EXT_ENTITLEMENTS" \
  | grep -qx 'group.com.sarveshjagtap.datebook'

echo "Prebuild validation: app and widget targets share one ActivityKit schema and App Group."
