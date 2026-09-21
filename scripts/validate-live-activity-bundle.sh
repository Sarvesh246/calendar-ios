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

# `strings <big binary> | grep -q PATTERN` is a false-negative trap under
# `pipefail`: `grep -q` exits the instant it finds a match, closing its
# stdin — `strings` is often still mid-write on a multi-MB Swift binary, so
# it gets SIGPIPE and errors ("strings: failed to flush output"). Under
# `pipefail` that makes the *pipeline's* exit status non-zero even though
# grep already found the match, so `|| fail ...` fires on a false alarm.
# Disabling pipefail for just this call (and reading grep's own status, not
# the pipeline's) fixes that without changing what's being checked.
binary_contains() {
  local file="$1" pattern="$2"
  set +o pipefail
  strings "$file" | grep -q "$pattern"
  local status=$?
  set -o pipefail
  return "$status"
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
binary_contains "$EXT/$EXECUTABLE" 'DatebookLiveActivity' || {
  fail "Compiled widget does not contain DatebookLiveActivity"
}
binary_contains "$APP/$APP_EXECUTABLE" 'DatebookLiveManager' || {
  fail "Shared Live Activity lifecycle manager is missing from the app target"
}

echo "Artifact manifest"
echo "  app: $APP_ID"
echo "  extension: $EXT_ID"
echo "  extension point: $POINT"
echo "  Live Activities: app=$SUPPORTS extension=$EXT_SUPPORTS"
echo "  extension bytes: $(stat -f%z "$EXT/$EXECUTABLE")"
