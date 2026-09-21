#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: validate-live-activity-bundle.sh /path/to/Datebook.app}"
EXT="$APP/PlugIns/DatebookWidgets.appex"
APP_PLIST="$APP/Info.plist"
EXT_PLIST="$EXT/Info.plist"

fail() {
  echo "::error title=Live Activity bundle validation::$1"
  exit 1
}

echo "Embedded plug-ins:"
find "$APP/PlugIns" -maxdepth 2 -print 2>/dev/null || true
test -d "$APP" || fail "Missing app bundle: $APP"
test -d "$EXT" || fail "Missing DatebookWidgets.appex"
plutil -lint "$APP_PLIST" "$EXT_PLIST"

APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PLIST")
EXT_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXT_PLIST")
POINT=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$EXT_PLIST")
SUPPORTS=$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' "$APP_PLIST")
EXT_SUPPORTS=$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' "$EXT_PLIST")
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$EXT_PLIST")
APP_EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PLIST")

test "$APP_ID" = 'com.sarveshjagtap.datebook' || fail "Unexpected app id: $APP_ID"
test "$EXT_ID" = 'com.sarveshjagtap.datebook.widgets' || fail "Unexpected widget id: $EXT_ID"
test "$POINT" = 'com.apple.widgetkit-extension' || fail "Wrong extension point: $POINT"
test "$SUPPORTS" = 'true' && test "$EXT_SUPPORTS" = 'true' || fail "Live Activity plist support missing: app=$SUPPORTS extension=$EXT_SUPPORTS"
test -x "$EXT/$EXECUTABLE" || fail "Widget executable missing"
strings "$EXT/$EXECUTABLE" | grep -q 'DatebookLiveActivity' || {
  fail "Compiled widget does not contain DatebookLiveActivity"
}
strings "$APP/$APP_EXECUTABLE" | grep -q 'DatebookLiveBridge' || {
  fail "Shared Live Activity lifecycle manager is missing from the app target"
}

echo "Artifact manifest"
echo "  app: $APP_ID"
echo "  extension: $EXT_ID"
echo "  extension point: $POINT"
echo "  Live Activities: app=$SUPPORTS extension=$EXT_SUPPORTS"
echo "  extension bytes: $(stat -f%z "$EXT/$EXECUTABLE")"
