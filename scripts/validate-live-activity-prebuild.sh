#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$PWD}"
PBXPROJ=$(find "$ROOT/ios" -name project.pbxproj -print -quit)
APP_ENTITLEMENTS=$(find "$ROOT/ios" -name '*.entitlements' ! -path '*/.targets/*' -print -quit)
EXT_ENTITLEMENTS=$(find "$ROOT/ios/.targets/DatebookWidgets" -name '*.entitlements' -print -quit 2>/dev/null || true)
SHARED_SOURCE="$ROOT/targets/_shared/DatebookLiveSupport.swift"
APP_SOURCE="$ROOT/modules/datebook-native/ios/DatebookLiveSupport.swift"

fail() {
  echo "::error title=Live Activity prebuild validation::$1"
  exit 1
}

echo "Generated entitlement files:"
find "$ROOT/ios" -name '*.entitlements' -print
test -f "$PBXPROJ" || fail "Missing generated Xcode project"
test -f "$SHARED_SOURCE" || fail "Missing shared ActivityKit source"
test -e "$APP_SOURCE" || fail "App target is not linked to the shared ActivityKit source"
test -f "$APP_ENTITLEMENTS" || fail "Missing app entitlements before archive"
test -f "$EXT_ENTITLEMENTS" || fail "Missing widget entitlements before archive"

grep -q 'struct DatebookLiveAttributes: ActivityAttributes' "$SHARED_SOURCE" || {
  fail "Shared source does not define DatebookLiveAttributes"
}
DUPLICATE_COUNT=$(grep -R --include='*.swift' --exclude='DatebookLiveSupport.swift' \
  -l 'struct DatebookLiveAttributes: ActivityAttributes' "$ROOT/modules" "$ROOT/targets" \
  | wc -l | tr -d ' ')
test "$DUPLICATE_COUNT" = "0" || fail "Found $DUPLICATE_COUNT duplicate DatebookLiveAttributes definition(s)"

cmp -s "$SHARED_SOURCE" "$APP_SOURCE" || fail "App and widget targets are not compiling the same ActivityKit source"
grep -q 'DatebookLiveManager.shared' "$ROOT/modules/datebook-native/ios/DatebookNativeModule.swift" || {
  fail "Expo module does not directly reference the shared Live Activity manager"
}

grep -q 'DatebookLiveActivity()' "$ROOT/targets/widget/DatebookWidgets.swift" || {
  fail "DatebookLiveActivity is not registered in the widget bundle"
}

grep -q 'group.com.sarveshjagtap.datebook' "$APP_ENTITLEMENTS" || fail "App entitlement lacks the Datebook App Group"
grep -q 'group.com.sarveshjagtap.datebook' "$EXT_ENTITLEMENTS" || fail "Widget entitlement lacks the Datebook App Group"

echo "Prebuild validation: app and widget targets share one ActivityKit schema and App Group."
