import { StatusBar } from "expo-status-bar";
import { useCallback, useEffect, useRef, useState } from "react";
import { AppState, BackHandler, Linking, Platform, StyleSheet, View } from "react-native";
import WebView, { type WebViewMessageEvent, type WebViewNavigation } from "react-native-webview";
import type { ShouldStartLoadRequest } from "react-native-webview/lib/WebViewTypes";
import * as WebBrowser from "expo-web-browser";
import * as Haptics from "expo-haptics";
import * as QuickActions from "expo-quick-actions";
import * as LocalAuthentication from "expo-local-authentication";
import * as SecureStore from "expo-secure-store";
import * as Notifications from "expo-notifications";
import * as ExpoLinking from "expo-linking";
import * as Location from "expo-location";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { LockScreen } from "./LockScreen";
import { DEFAULT_NATIVE_CHROME, NativeChrome, type NativeChromeState } from "./NativeChrome";
import {
  applySnapshot,
  consumeInbox,
  notificationDeepLink,
  requestNativeNotifications,
} from "./lib/apply-snapshot";
import type { NativeSnapshot } from "./lib/snapshot-types";

WebBrowser.maybeCompleteAuthSession();

const APP_ORIGIN = "https://datebookcalendar.vercel.app";
const OAUTH_RETURN_SCHEME = "datebook://auth-callback";
// Explicit, verifiable marker the web app checks via navigator.userAgent to
// know it's running inside this wrapper (used to pick the OAuth redirect
// target). More reliable than relying on react-native-webview's auto-injected
// window.ReactNativeWebView bridge object, which wasn't consistently truthy
// at the moment the sign-in handler ran.
const USER_AGENT_MARKER = "DatebookNativeApp";
// signInWithOAuth first navigates to Supabase's own authorize endpoint
// (which then 302s to Google) — that first hop has to be caught here, not
// just accounts.google.com, or it falls through to the generic external-link
// branch and opens real Safari instead of the in-app auth sheet. Google also
// refuses to render its sign-in page inside an embedded WebView at all
// ("disallowed_useragent"), so both hops route through the system browser.
function isOAuthKickoff(url: string) {
  return url.includes("/auth/v1/authorize") || url.includes("accounts.google.com");
}

type AppLockState = { enabled: boolean; requireAfterMinutes: number };
const DEFAULT_APP_LOCK: AppLockState = { enabled: false, requireAfterMinutes: 5 };
const APP_LOCK_KEY = "datebook.appLock";

async function readAppLock(): Promise<AppLockState> {
  try {
    const raw = await SecureStore.getItemAsync(APP_LOCK_KEY);
    if (!raw) return DEFAULT_APP_LOCK;
    return { ...DEFAULT_APP_LOCK, ...JSON.parse(raw) };
  } catch {
    return DEFAULT_APP_LOCK;
  }
}

async function writeAppLock(state: AppLockState) {
  try {
    await SecureStore.setItemAsync(APP_LOCK_KEY, JSON.stringify(state));
  } catch {
    /* ignore */
  }
}

/** Where each Home Screen Quick Action deep-links; `intent` is consumed once by AppShell. */
function quickActionTarget(id: string) {
  if (id === "compose") return `${APP_ORIGIN}/today?intent=compose`;
  if (id === "focus") return `${APP_ORIGIN}/today?intent=focus`;
  return `${APP_ORIGIN}/today`;
}

function openUrlToApp(url: string) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol === "datebook:") {
      const intent = parsed.searchParams.get("intent") || parsed.hostname;
      const item = parsed.searchParams.get("item");
      const prefill = parsed.searchParams.get("prefill") ?? parsed.searchParams.get("text");
      const q = new URLSearchParams();
      if (intent && intent !== "open") q.set("intent", intent === "inbox" ? "inbox" : intent);
      if (item) q.set("item", item);
      if (prefill) q.set("prefill", prefill);
      const path = intent === "inbox" || parsed.pathname.includes("settings") ? "/settings" : "/today";
      return `${APP_ORIGIN}${path}${q.toString() ? `?${q}` : ""}`;
    }
  } catch {
    /* fall through */
  }
  return url;
}

export default function App() {
  const webviewRef = useRef<WebView>(null);
  const [uri, setUri] = useState(APP_ORIGIN);
  const canGoBack = useRef(false);
  const [chrome, setChrome] = useState<NativeChromeState>(DEFAULT_NATIVE_CHROME);
  const [focusRunning, setFocusRunning] = useState(false);
  const pendingNavigation = useRef<{ url: string; startedAt: number } | null>(null);

  // App Lock: native is the source of truth (it must gate content before any
  // web JS runs), the Settings toggle on the web side is a remote control for
  // it over the bridge. `lockReady` blocks the WebView entirely until the
  // stored state is read, so locked content never flashes on cold launch.
  const appLock = useRef<AppLockState>(DEFAULT_APP_LOCK);
  const [lockReady, setLockReady] = useState(false);
  const [locked, setLocked] = useState(false);
  const [privacyCovered, setPrivacyCovered] = useState(false);
  const [authenticating, setAuthenticating] = useState(false);
  const [appIsActive, setAppIsActive] = useState(AppState.currentState === "active");
  const backgroundedAt = useRef<number | null>(null);
  const authAttemptedForLock = useRef(false);
  const authenticationInFlight = useRef(false);

  useEffect(() => {
    void readAppLock().then((state) => {
      appLock.current = state;
      authAttemptedForLock.current = false;
      setLocked(state.enabled);
      setLockReady(true);
    });
  }, []);

  const tryUnlock = useCallback(async () => {
    authenticationInFlight.current = true;
    setAuthenticating(true);
    try {
      const result = await LocalAuthentication.authenticateAsync({
        promptMessage: "Unlock Datebook",
        cancelLabel: "Cancel",
        fallbackLabel: "Use Passcode",
        disableDeviceFallback: false,
      });
      if (result.success) setLocked(false);
    } catch {
      // Keep the native lock boundary in place; the visible unlock button lets
      // the user retry if iOS temporarily rejects or interrupts the request.
    } finally {
      authenticationInFlight.current = false;
      setAuthenticating(false);
    }
  }, []);

  useEffect(() => {
    if (
      lockReady &&
      locked &&
      !authenticating &&
      !authAttemptedForLock.current &&
      appIsActive
    ) {
      authAttemptedForLock.current = true;
      void tryUnlock();
    }
  }, [lockReady, locked, authenticating, appIsActive, tryUnlock]);

  useEffect(() => {
    const sub = AppState.addEventListener("change", (next) => {
      setAppIsActive(next === "active");
      // The system Face ID/passcode sheet itself produces inactive/active
      // transitions. They are not real backgrounding and must not restart an
      // immediate-lock cycle after a successful authentication.
      if (authenticationInFlight.current) return;
      if (next === "background" || next === "inactive") {
        backgroundedAt.current = Date.now();
        if (appLock.current.enabled) setPrivacyCovered(true);
        return;
      }
      if (next !== "active") return;
      const state = appLock.current;
      const since = backgroundedAt.current;
      backgroundedAt.current = null;
      // `since === null` means this "active" is the cold-launch transition,
      // already handled by the readAppLock effect above.
      if (!state.enabled || since === null) {
        setPrivacyCovered(false);
        return;
      }
      // -1 means "only when the app was fully closed" — backgrounding alone
      // never re-locks it.
      if (state.requireAfterMinutes === -1) {
        setPrivacyCovered(false);
        return;
      }
      const elapsedMinutes = (Date.now() - since) / 60000;
      if (elapsedMinutes >= state.requireAfterMinutes) {
        authAttemptedForLock.current = false;
        setLocked(true);
      } else {
        setPrivacyCovered(false);
      }
    });
    return () => sub.remove();
  }, []);

  // Home Screen Quick Actions — static entries, resolved on cold launch
  // (QuickActions.initial) and while the app is already running (addListener).
  useEffect(() => {
    QuickActions.setItems([
      { id: "compose", title: "Quick add", icon: "compose" },
      { id: "today", title: "Today", icon: "date" },
      { id: "focus", title: "Focus", icon: "time" },
    ]);
    if (QuickActions.initial) setUri(quickActionTarget(QuickActions.initial.id));
    const sub = QuickActions.addListener((action) => setUri(quickActionTarget(action.id)));
    return () => sub.remove();
  }, []);

  useEffect(() => {
    const sub = Notifications.addNotificationResponseReceivedListener((response) => {
      const target = notificationDeepLink(response);
      if (target) setUri(target);
    });
    void Notifications.getLastNotificationResponseAsync().then((response) => {
      if (!response) return;
      const target = notificationDeepLink(response);
      if (target) setUri(target);
    });
    return () => sub.remove();
  }, []);

  useEffect(() => {
    const apply = (url: string) => setUri(openUrlToApp(url));
    const sub = ExpoLinking.addEventListener("url", (e) => apply(e.url));
    void ExpoLinking.getInitialURL().then((url) => {
      if (url) apply(url);
    });
    return () => sub.remove();
  }, []);

  const pushBridge = useCallback((type: string, payload: unknown) => {
    const script = `window.__datebookBridge && window.__datebookBridge.dispatch(${JSON.stringify({ type, payload })}); true;`;
    webviewRef.current?.injectJavaScript(script);
  }, []);

  useEffect(() => {
    if (!lockReady || locked) return;
    void consumeInbox(pushBridge).then((url) => {
      if (url) setUri(url);
    });
  }, [lockReady, locked, pushBridge]);

  // Messages posted from lib/native-bridge.ts on the web side.
  const onMessage = useCallback(
    (event: WebViewMessageEvent) => {
      let message: { type: string; payload?: Record<string, unknown> };
      try {
        message = JSON.parse(event.nativeEvent.data);
      } catch {
        return;
      }

      if (message.type === "haptic") {
        const kind = message.payload?.kind;
        if (kind === "success") void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        else if (kind === "warn") void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
        else if (kind === "selection") void Haptics.selectionAsync();
        else void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        return;
      }

      if (message.type === "getAppLock") {
        pushBridge("appLockState", appLock.current);
        return;
      }

      if (message.type === "setAppLock") {
        const next: AppLockState = {
          enabled: Boolean(message.payload?.enabled),
          requireAfterMinutes: Number(message.payload?.requireAfterMinutes ?? 0),
        };
        appLock.current = next;
        void writeAppLock(next);
        if (!next.enabled) {
          authAttemptedForLock.current = false;
          setLocked(false);
          setPrivacyCovered(false);
        }
        return;
      }

      if (message.type === "requestNativeNotifications") {
        void requestNativeNotifications().then((granted) => {
          pushBridge("nativeNotificationState", { granted });
        });
        return;
      }

      if (message.type === "nativeSnapshot" && message.payload) {
        const snapshot = message.payload as unknown as NativeSnapshot;
        setFocusRunning(Boolean(snapshot.liveFocus?.running));
        void applySnapshot(snapshot);
        return;
      }

      if (message.type === "nativeChromeState" && message.payload) {
        const next = message.payload as unknown as NativeChromeState;
        const pending = pendingNavigation.current;
        if (pending && next.pathname === pending.url) {
          pendingNavigation.current = null;
          setChrome(next);
        } else if (pending && Date.now() - pending.startedAt < 1800) {
          // The web shell can publish its previous route once more while Next
          // commits a native tab request. Keep every other chrome field fresh,
          // but never let that stale route move the selection back underneath
          // the user's finger.
          setChrome((current) => ({ ...next, pathname: current.pathname }));
        } else {
          pendingNavigation.current = null;
          setChrome(next);
        }
        return;
      }

      if (message.type === "requestPlace") {
        void (async () => {
          const perm = await Location.requestForegroundPermissionsAsync();
          if (perm.status !== "granted") return;
          const here = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
          let name = typeof message.payload?.name === "string" ? message.payload.name : "";
          try {
            const geo = await Location.reverseGeocodeAsync({
              latitude: here.coords.latitude,
              longitude: here.coords.longitude,
            });
            const hit = geo[0];
            if (!name && hit) name = [hit.name, hit.street, hit.city].filter(Boolean).join(", ");
          } catch {
            /* keep typed name */
          }
          pushBridge("nativePlace", {
            lat: here.coords.latitude,
            lng: here.coords.longitude,
            name: name || "Current location",
          });
        })();
        return;
      }

      if (message.type === "getNativeCapabilities") {
        pushBridge("nativeCapabilities", {
          calendar: "Datebook can add a calendar named Datebook in Calendar.app.",
        });
      }
    },
    [pushBridge]
  );

  const runOAuthInSystemBrowser = useCallback(async (authUrl: string) => {
    const result = await WebBrowser.openAuthSessionAsync(authUrl, OAUTH_RETURN_SCHEME);
    if (result.type === "success" && result.url) {
      const hashIndex = result.url.indexOf("#");
      const hash = hashIndex >= 0 ? result.url.slice(hashIndex) : "";
      setUri(`${APP_ORIGIN}/${hash}`);
    }
  }, []);

  const onShouldStartLoadWithRequest = useCallback(
    (request: ShouldStartLoadRequest) => {
      const { url } = request;

      if (url.startsWith(APP_ORIGIN) || url.startsWith("about:") || url.startsWith("data:")) {
        return true;
      }

      if (isOAuthKickoff(url)) {
        void runOAuthInSystemBrowser(url);
        return false;
      }

      // Anything else (mailto:, tel:, an imported item's external link, ...)
      // leaves the app instead of navigating the embedded view away from Datebook.
      void Linking.openURL(url);
      return false;
    },
    [runOAuthInSystemBrowser]
  );

  const onNavigationStateChange = useCallback((navState: WebViewNavigation) => {
    canGoBack.current = navState.canGoBack;
  }, []);

  if (Platform.OS === "android") {
    BackHandler.addEventListener("hardwareBackPress", () => {
      if (canGoBack.current) {
        webviewRef.current?.goBack();
        return true;
      }
      return false;
    });
  }

  if (!lockReady) {
    return (
      <View style={styles.container}>
        <StatusBar style="light" />
      </View>
    );
  }

  // A locked app is a real render boundary, not a visual overlay. The WebView
  // does not exist until authentication succeeds, so protected content cannot
  // flash through behind the Face ID sheet or appear if a layout style fails.
  if (locked) {
    return (
      <SafeAreaProvider>
        <View style={styles.container}>
          <StatusBar style="light" />
          <LockScreen authenticating={authenticating} onUnlock={() => void tryUnlock()} />
        </View>
      </SafeAreaProvider>
    );
  }

  return (
    <SafeAreaProvider>
      <View style={styles.container}>
        <StatusBar style={chrome.appearance === "light" ? "dark" : "light"} />
        <WebView
          ref={webviewRef}
          source={{ uri }}
          style={styles.webview}
          onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
          onNavigationStateChange={onNavigationStateChange}
          onMessage={onMessage}
          setSupportMultipleWindows={false}
          allowsBackForwardNavigationGestures
          sharedCookiesEnabled
          automaticallyAdjustContentInsets={false}
          contentInsetAdjustmentBehavior="never"
          applicationNameForUserAgent={USER_AGENT_MARKER}
          injectedJavaScriptBeforeContentLoaded={
            "document.documentElement.classList.add('native-ios'); true;"
          }
          // Datebook is local-first (Zustand + localStorage); this keeps that
          // storage in the app's own container across launches and resigns.
          domStorageEnabled
          decelerationRate="normal"
        />
        {!locked && (
          <NativeChrome
            state={chrome}
            focusRunning={focusRunning}
            onAction={(action) => {
              void Haptics.selectionAsync();
              if (action.type === "navigate") {
                pendingNavigation.current = { url: action.url, startedAt: Date.now() };
                setChrome((current) => ({ ...current, pathname: action.url }));
              }
              pushBridge("nativeIntent", action);
            }}
          />
        )}
        {privacyCovered && (
          <View pointerEvents="none" style={styles.privacyCover}>
            <StatusBar style="light" />
          </View>
        )}
      </View>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#07070a",
  },
  webview: {
    flex: 1,
    backgroundColor: "#07070a",
  },
  privacyCover: {
    position: "absolute",
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    backgroundColor: "#07070a",
  },
});
