import { useEffect, useMemo, useRef, useState } from "react";
import {
  AccessibilityInfo,
  Animated,
  Easing,
  Image,
  Platform,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import * as LocalAuthentication from "expo-local-authentication";
import { GlassView, isGlassEffectAPIAvailable } from "expo-glass-effect";

type Props = {
  authenticating: boolean;
  onUnlock: () => void;
};

/**
 * Native lock veil. Same dark material as the splash so Face ID never
 * flashes a different app; the mark, word, and a single unlock control
 * are the whole composition.
 */
export function LockScreen({ authenticating, onUnlock }: Props) {
  const [label, setLabel] = useState("Unlock with Face ID");
  const [reduceTransparency, setReduceTransparency] = useState(false);
  const opacity = useRef(new Animated.Value(0)).current;
  const rise = useRef(new Animated.Value(10)).current;

  useEffect(() => {
    void AccessibilityInfo.isReduceTransparencyEnabled().then(setReduceTransparency);
    const sub = AccessibilityInfo.addEventListener("reduceTransparencyChanged", setReduceTransparency);
    return () => sub.remove();
  }, []);

  useEffect(() => {
    let cancelled = false;
    void LocalAuthentication.supportedAuthenticationTypesAsync().then((types) => {
      if (cancelled) return;
      if (types.includes(LocalAuthentication.AuthenticationType.FACIAL_RECOGNITION)) {
        setLabel("Unlock with Face ID");
      } else if (types.includes(LocalAuthentication.AuthenticationType.FINGERPRINT)) {
        setLabel("Unlock with Touch ID");
      } else {
        setLabel("Unlock with Passcode");
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let reduced = false;
    void AccessibilityInfo.isReduceMotionEnabled().then((value) => {
      reduced = value;
      if (value) {
        opacity.setValue(1);
        rise.setValue(0);
        return;
      }
      Animated.parallel([
        Animated.timing(opacity, {
          toValue: 1,
          duration: 420,
          easing: Easing.out(Easing.cubic),
          useNativeDriver: true,
        }),
        Animated.timing(rise, {
          toValue: 0,
          duration: 480,
          easing: Easing.out(Easing.cubic),
          useNativeDriver: true,
        }),
      ]).start();
    });
    return () => {
      if (!reduced) opacity.stopAnimation();
    };
  }, [opacity, rise]);

  const markStyle = useMemo(
    () => [{ opacity, transform: [{ translateY: rise }] }],
    [opacity, rise]
  );
  const nativeGlass = Platform.OS === "ios" && isGlassEffectAPIAvailable() && !reduceTransparency;

  return (
    <View style={styles.overlay} accessibilityViewIsModal>
      <SafeAreaView style={styles.safe}>
        <Animated.View style={[styles.stage, markStyle]}>
          <View pointerEvents="none" style={styles.bloom} />
          {nativeGlass ? (
            <GlassView colorScheme="dark" glassEffectStyle="regular" style={styles.plate}>
              <Image source={require("./assets/icon.png")} style={styles.mark} accessibilityIgnoresInvertColors />
            </GlassView>
          ) : (
            <View style={styles.plate}>
              <Image source={require("./assets/icon.png")} style={styles.mark} accessibilityIgnoresInvertColors />
            </View>
          )}
          <Text style={styles.wordmark}>Datebook</Text>
          <Text style={styles.kicker}>Locked</Text>
        </Animated.View>

        <View style={styles.actions}>
          {nativeGlass ? (
            <GlassView colorScheme="dark" glassEffectStyle="regular" tintColor="#0a84ff" style={styles.button}>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={label}
                disabled={authenticating}
                onPress={onUnlock}
                style={({ pressed }) => [styles.buttonPressable, pressed && styles.buttonPressed, authenticating && styles.buttonBusy]}
              >
                <Text style={styles.buttonText}>{authenticating ? "Unlocking…" : label}</Text>
              </Pressable>
            </GlassView>
          ) : (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={label}
              disabled={authenticating}
              onPress={onUnlock}
              style={({ pressed }) => [styles.button, styles.buttonFallback, pressed && styles.buttonPressed, authenticating && styles.buttonBusy]}
            >
              <Text style={styles.buttonText}>{authenticating ? "Unlocking…" : label}</Text>
            </Pressable>
          )}
          <Text style={styles.hint}>Your calendar stays private until you unlock.</Text>
        </View>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    position: "absolute",
    inset: 0,
    backgroundColor: "#07070a",
  },
  safe: {
    flex: 1,
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 28,
    paddingTop: 56,
    paddingBottom: 28,
  },
  stage: {
    alignItems: "center",
    marginTop: 36,
  },
  bloom: {
    position: "absolute",
    width: 280,
    height: 280,
    borderRadius: 140,
    backgroundColor: "rgba(10, 132, 255, 0.18)",
    top: -86,
  },
  plate: {
    height: 108,
    width: 108,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 28,
    backgroundColor: "rgba(255, 255, 255, 0.06)",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255, 255, 255, 0.12)",
    shadowColor: "#000",
    shadowOpacity: 0.45,
    shadowRadius: 28,
    shadowOffset: { width: 0, height: 18 },
  },
  mark: {
    height: 84,
    width: 84,
    borderRadius: 22,
  },
  wordmark: {
    marginTop: 22,
    color: "#f4f4f5",
    fontSize: 22,
    fontWeight: "600",
    letterSpacing: 0.4,
  },
  kicker: {
    marginTop: 6,
    color: "rgba(244, 244, 245, 0.48)",
    fontSize: 14,
    fontWeight: "500",
    letterSpacing: 0.2,
  },
  actions: {
    width: "100%",
    maxWidth: 340,
    alignItems: "center",
    gap: 14,
    paddingBottom: 12,
  },
  button: {
    width: "100%",
    minHeight: 52,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 26,
    overflow: "hidden",
  },
  buttonFallback: {
    backgroundColor: "#0a84ff",
  },
  buttonPressable: {
    flex: 1,
    width: "100%",
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 26,
  },
  buttonPressed: {
    opacity: 0.88,
  },
  buttonBusy: {
    opacity: 0.7,
  },
  buttonText: {
    color: "#ffffff",
    fontSize: 16,
    fontWeight: "600",
    letterSpacing: 0.2,
  },
  hint: {
    color: "rgba(244, 244, 245, 0.4)",
    fontSize: 13,
    textAlign: "center",
    lineHeight: 18,
  },
});
