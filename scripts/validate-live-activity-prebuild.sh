#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$PWD}"
PBXPROJ=$(find "$ROOT/ios" -name project.pbxproj -print -quit)
APP_ENTITLEMENTS=$(find "$ROOT/ios" -path '*/Datebook*.entitlements' ! -path '*/.targets/*' -print -quit)
EXT_ENTITLEMENTS=$(find "$ROOT/ios/.targets/DatebookWidgets" -name '*.entitlements' -print -quit 2>/dev/null || true)
SHARED_SOURCE="$ROOT/targets/widget/_shared/DatebookLiveSupport.swift"

fail() {
  echo "::error title=Live Activity prebuild validation::$1"
  exit 1
}

echo "Generated entitlement files:"
find "$ROOT/ios" -name '*.entitlements' -print
test -f "$PBXPROJ" || fail "Missing generated Xcode project"
test -f "$SHARED_SOURCE" || fail "Missing shared ActivityKit source"
test -f "$APP_ENTITLEMENTS" || fail "Missing app entitlements before archive"
test -f "$EXT_ENTITLEMENTS" || fail "Missing widget entitlements before archive"

DEFINITION_COUNT=$(grep -R --include='*.swift' -l 'struct DatebookLiveAttributes: ActivityAttributes' \
  "$ROOT/modules" "$ROOT/targets" | wc -l | tr -d ' ')
test "$DEFINITION_COUNT" = "1" || fail "Expected one shared DatebookLiveAttributes definition, found $DEFINITION_COUNT"

grep -q 'DatebookWidgets' "$PBXPROJ" || fail "Widget target missing from project"
grep -q '_shared' "$PBXPROJ" || fail "Shared source group missing from project"
grep -q 'DatebookLiveActivity()' "$ROOT/targets/widget/DatebookWidgets.swift" || {
  fail "DatebookLiveActivity is not registered in the widget bundle"
}

grep -q 'group.com.sarveshjagtap.datebook' "$APP_ENTITLEMENTS" || fail "App entitlement lacks the Datebook App Group"
grep -q 'group.com.sarveshjagtap.datebook' "$EXT_ENTITLEMENTS" || fail "Widget entitlement lacks the Datebook App Group"

echo "Prebuild validation: app and widget targets share one ActivityKit schema and App Group."
