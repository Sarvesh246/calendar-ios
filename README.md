# Datebook for iOS

The native shell for [Datebook](https://github.com/Sarvesh246/calendar). It is an Expo app that hosts the live site (`https://datebookcalendar.vercel.app`) in a WebView and adds the things a browser cannot do: Face ID lock, haptics, quick actions, iOS reminders, widgets, Spotlight, and Live Activities. The WebView identifies itself with the `DatebookNativeApp` user-agent marker, which is how the web app knows to use the native bridge instead of web push.

Because the UI is the website, web changes ship through Vercel with no new build. A new IPA is only needed when something in this repo changes.

## Prerequisites

- Node 24 (see `.nvmrc`) and npm
- To build locally: macOS with Xcode and CocoaPods. CI builds the unsigned IPA on a macOS runner, so you do not need a Mac for that.
- To install on a device: an Apple development identity and provisioning profiles for the app and the widget extension.

## Getting started

```bash
npm install
npx tsc --noEmit        # typecheck
npm run lint
```

The `ios/` directory is generated and not committed. To produce it locally on a Mac:

```bash
npx expo prebuild --platform ios
```

There are no environment variables. The origin the app loads is `APP_ORIGIN` in `App.tsx`.

## Scripts

| Command                           | What it does                             |
| --------------------------------- | ---------------------------------------- |
| `npm run typecheck`               | `tsc --noEmit`                           |
| `npm run lint`                    | ESLint (`eslint-config-expo`)            |
| `npm run format` / `format:check` | Prettier                                 |
| `npm run security:secrets`        | Scan tracked files for committed secrets |

## How it is put together

- `App.tsx` is the WebView host: navigation, deep links, quick actions, and recovery when iOS kills the WebView in the background.
- `NativeChrome.tsx` draws the bottom navigation as one connected Liquid Glass capsule for Today, Calendar and Agenda, with a sliding selected pill and a separate Add button.
- `modules/datebook-native` is a local Expo module that talks to ActivityKit.
- `targets/widget` is the `DatebookWidgets` extension (home-screen widgets and the Live Activity, which covers both the lock screen and the Dynamic Island). `targets/share` is the share extension. Both are wired up by `@bacons/apple-targets`.
- `lib/apply-snapshot.ts` turns the snapshot the web app posts into notifications, calendar entries, widget data and Live Activity updates.

## Building and installing

Pushes to `master` that touch native code run the **Build unsigned iOS .ipa** workflow, which archives the app, validates that the widget extension and App Group are embedded, and uploads `Datebook-unsigned.ipa` as an artifact. The IPA is unsigned on purpose. Re-signing must keep `DatebookWidgets.appex` and the App Group `group.com.sarveshjagtap.datebook`; the exact steps and a verification script are in [docs/live-activity-sideloading.md](docs/live-activity-sideloading.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow [Conventional Commits](https://www.conventionalcommits.org/).

## License

[MIT](LICENSE)
