import { StatusBar } from "expo-status-bar";
import { useCallback, useRef, useState } from "react";
import { BackHandler, Linking, Platform, SafeAreaView, StyleSheet } from "react-native";
import WebView, { type WebViewNavigation } from "react-native-webview";
import type { ShouldStartLoadRequest } from "react-native-webview/lib/WebViewTypes";
import * as WebBrowser from "expo-web-browser";

WebBrowser.maybeCompleteAuthSession();

const APP_ORIGIN = "https://datebookcalendar.vercel.app";
const OAUTH_RETURN_SCHEME = "datebook://auth-callback";
// Google refuses to render its sign-in page inside an embedded WebView
// ("disallowed_useragent"), so any navigation toward it is handed off to
// the system browser (ASWebAuthenticationSession) instead of loading here.
const OAUTH_HOSTS = ["accounts.google.com"];

export default function App() {
  const webviewRef = useRef<WebView>(null);
  const [uri, setUri] = useState(APP_ORIGIN);
  const canGoBack = useRef(false);

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

      if (OAUTH_HOSTS.some((host) => url.includes(host))) {
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

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="light" />
      <WebView
        ref={webviewRef}
        source={{ uri }}
        style={styles.webview}
        onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
        onNavigationStateChange={onNavigationStateChange}
        setSupportMultipleWindows={false}
        allowsBackForwardNavigationGestures
        sharedCookiesEnabled
        // Datebook is local-first (Zustand + localStorage); this keeps that
        // storage in the app's own container across launches and resigns.
        domStorageEnabled
        decelerationRate="normal"
      />
    </SafeAreaView>
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
});
