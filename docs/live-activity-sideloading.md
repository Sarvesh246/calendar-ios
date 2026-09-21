# Live Activity sideloading and device verification

The CI artifact is intentionally unsigned. Its successful archive proves that
the app and widget extension compile and that `DatebookWidgets.appex` is
embedded. It does not prove that an external signer preserved extension
registration or entitlements on the installed phone.

## Re-signing requirements

Use one Apple development identity/team and compatible provisioning profiles
for both bundle identifiers:

- App: `com.sarveshjagtap.datebook`
- Widget: `com.sarveshjagtap.datebook.widgets`

Both profiles/signatures must contain the App Group
`group.com.sarveshjagtap.datebook`. Sign in containment order:

1. Nested frameworks and dynamic libraries in `Datebook.app/Frameworks`.
2. `Datebook.app/PlugIns/DatebookWidgets.appex` with the widget profile and
   widget entitlements.
3. `Datebook.app` with the app profile and app entitlements.

Never use a signer option that removes application groups or drops nested
extensions. After re-signing, run on macOS:

```bash
./scripts/verify-signed-ipa.sh /path/to/Datebook-signed.ipa
```

## Physical iPhone test

1. Install the verified signed IPA and open Datebook once.
2. In iOS Settings, confirm Live Activities and Lock Screen access are enabled
   for Datebook.
3. In Datebook Settings > Account & sync > Live Activity, tap **Refresh
   Status**. Confirm `supported`, `activitiesEnabled`, and `extensionPresent`
   are true.
4. Tap **Start Test Live Activity**. Confirm the status is Active, a real
   Activity ID appears in diagnostics, and `activeCount` is 1.
5. Lock the phone and inspect the full and compact Lock Screen presentations.
6. On a Dynamic Island phone, inspect compact leading/trailing, minimal (while
   another activity is present), and press-and-hold expanded presentation.
7. Tap the activity and confirm Datebook opens Today.
8. Return to Datebook so its real schedule snapshot replaces the test state.
9. Verify upcoming countdown, active-event progress, missing-location layout,
   and a long title.
10. Start Focus. Confirm focus takes priority, its countdown/progress updates,
    and tapping opens Focus. End Focus and confirm the activity returns to the
    day overview rather than disappearing.
11. Force-quit and relaunch Datebook. Confirm the same Activity ID is adopted
    and no duplicate appears.
12. Test light wallpaper, dark wallpaper, large text, and dimmed Always-On
    display.
13. Select **Hide private details** and confirm event/focus titles and locations
    are absent.
14. Tap **Stop Live Activity** and confirm `activeCount` becomes 0 and the card
    disappears.
15. Re-run `verify-signed-ipa.sh` against the exact IPA installed on the phone.

ActivityKit controls visibility and lifetime. With no Datebook APNs provider,
the app can reconcile while foregrounded and during system-granted execution,
but it cannot guarantee a local activity will be restarted after iOS ends it
while the app remains suspended.
