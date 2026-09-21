#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: validate-live-activity-bundle.sh /path/to/Datebook.app}"
EXT="$APP/PlugIns/DatebookWidgets.appex"
APP_PLIST="$APP/Info.plist"
EXT_PLIST="$EXT/Info.plist"

test -d "$APP" || { echo "Missing app bundle: $APP"; exit 1; }
test -d "$EXT" || { echo "Missing DatebookWidgets.appex"; exit 1; }
plutil -lint "$APP_PLIST" "$EXT_PLIST"

APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PLIST")
EXT_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXT_PLIST")
POINT=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$EXT_PLIST")
SUPPORTS=$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' "$APP_PLIST")
EXT_SUPPORTS=$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' "$EXT_PLIST")
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$EXT_PLIST")
APP_EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PLIST")

test "$APP_ID" = 'com.sarveshjagtap.datebook' || { echo "Unexpected app id: $APP_ID"; exit 1; }
test "$EXT_ID" = 'com.sarveshjagtap.datebook.widgets' || { echo "Unexpected widget id: $EXT_ID"; exit 1; }
test "$POINT" = 'com.apple.widgetkit-extension' || { echo "Wrong extension point: $POINT"; exit 1; }
test "$SUPPORTS" = 'true' && test "$EXT_SUPPORTS" = 'true' || { echo "Live Activity plist support missing"; exit 1; }
test -x "$EXT/$EXECUTABLE" || { echo "Widget executable missing"; exit 1; }
strings "$EXT/$EXECUTABLE" | grep -q 'DatebookLiveActivity' || {
  echo "Compiled widget does not contain DatebookLiveActivity"
  exit 1
}
strings "$APP/$APP_EXECUTABLE" | grep -q 'DatebookLiveBridge' || {
  echo "Shared Live Activity lifecycle manager is missing from the app target"
  exit 1
}

echo "Artifact manifest"
echo "  app: $APP_ID"
echo "  extension: $EXT_ID"
echo "  extension point: $POINT"
echo "  Live Activities: app=$SUPPORTS extension=$EXT_SUPPORTS"
echo "  extension bytes: $(stat -f%z "$EXT/$EXECUTABLE")"
