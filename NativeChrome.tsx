import { GlassView, isGlassEffectAPIAvailable } from "expo-glass-effect";
import { SymbolView, type SFSymbol } from "expo-symbols";
import { useEffect, useState, type ReactNode } from "react";
import {
  AccessibilityInfo,
  Keyboard,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
  type ViewStyle,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

export type NativeChromeState = {
  ready: boolean;
  pathname: string;
  focusMode: boolean;
  obscured: boolean;
  inRoom: boolean;
  filtersActive: boolean;
  appearance: "light" | "dark";
  colors: {
    surface: string;
    ink: string;
    inkSoft: string;
    accent: string;
    accentInk: string;
  };
};

export const DEFAULT_NATIVE_CHROME: NativeChromeState = {
  ready: false,
  pathname: "/today",
  focusMode: false,
  obscured: false,
  inRoom: false,
  filtersActive: false,
  appearance: "dark",
  colors: {
    surface: "#2c2c2e",
    ink: "#f5f5f7",
    inkSoft: "#aeaeb2",
    accent: "#0a84ff",
    accentInk: "#ffffff",
  },
};

type ChromeAction =
  | { type: "navigate"; url: string }
  | { type: "compose" }
  | { type: "ask" | "search" | "filters" | "exitFocus" | "pauseFocus" | "resumeFocus" | "endFocus" };

type Props = {
  state: NativeChromeState;
  focusRunning: boolean;
  onAction: (action: ChromeAction) => void;
};

const TABS: { label: string; url: string; symbol: SFSymbol }[] = [
  { label: "Today", url: "/today", symbol: "sun.max" },
  { label: "Calendar", url: "/calendar", symbol: "calendar" },
  { label: "Agenda", url: "/agenda", symbol: "list.bullet" },
];

function alpha(hex: string, opacity: number) {
  const raw = hex.trim().replace("#", "");
  const expanded = raw.length === 3 ? raw.split("").map((part) => part + part).join("") : raw;
  if (!/^[0-9a-f]{6}$/i.test(expanded)) return `rgba(44, 44, 46, ${opacity})`;
  const value = Number.parseInt(expanded, 16);
  return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${opacity})`;
}

function GlassSurface({
  children,
  state,
  reduceTransparency,
  style,
  tintColor,
}: {
  children: ReactNode;
  state: NativeChromeState;
  reduceTransparency: boolean;
  style: ViewStyle | ViewStyle[];
  tintColor?: string;
}) {
  const nativeGlass = Platform.OS === "ios" && isGlassEffectAPIAvailable() && !reduceTransparency;
  if (nativeGlass) {
    return (
      <GlassView
        colorScheme={state.appearance}
        glassEffectStyle="regular"
        tintColor={tintColor}
        style={style}
      >
        {children}
      </GlassView>
    );
  }
  return (
    <View
      style={[
        style,
        styles.fallbackSurface,
        {
          backgroundColor: alpha(state.colors.surface, reduceTransparency ? 0.98 : 0.9),
          borderColor: alpha(state.colors.ink, state.appearance === "dark" ? 0.15 : 0.1),
        },
      ]}
    >
      {children}
    </View>
  );
}

function ChromeButton({
  label,
  symbol,
  state,
  active = false,
  showLabel = false,
  badge = false,
  onPress,
}: {
  label: string;
  symbol: SFSymbol;
  state: NativeChromeState;
  active?: boolean;
  showLabel?: boolean;
  badge?: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ selected: active }}
      hitSlop={4}
      onPress={onPress}
      style={({ pressed }) => [
        styles.chromeButton,
        showLabel && styles.chromeButtonLabelled,
        active && { backgroundColor: alpha(state.colors.accent, state.appearance === "dark" ? 0.22 : 0.14) },
        pressed && styles.pressed,
      ]}
    >
      <View>
        <SymbolView
          name={symbol}
          size={showLabel ? 17 : 18}
          weight={active ? "semibold" : "medium"}
          tintColor={active ? state.colors.accent : state.colors.inkSoft}
        />
        {badge && <View style={[styles.badge, { backgroundColor: state.colors.accent }]} />}
      </View>
      {showLabel && (
        <Text style={[styles.compactLabel, { color: active ? state.colors.accent : state.colors.ink }]}>
          {label}
        </Text>
      )}
    </Pressable>
  );
}

export function NativeChrome({ state, focusRunning, onAction }: Props) {
  const insets = useSafeAreaInsets();
  const [reduceTransparency, setReduceTransparency] = useState(false);
  const [keyboardVisible, setKeyboardVisible] = useState(false);

  useEffect(() => {
    void AccessibilityInfo.isReduceTransparencyEnabled().then(setReduceTransparency);
    const sub = AccessibilityInfo.addEventListener("reduceTransparencyChanged", setReduceTransparency);
    return () => sub.remove();
  }, []);

  useEffect(() => {
    const show = Keyboard.addListener("keyboardWillShow", () => setKeyboardVisible(true));
    const hide = Keyboard.addListener("keyboardWillHide", () => setKeyboardVisible(false));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);

  if (!state.ready || state.obscured) return null;

  if (state.focusMode) {
    return (
      <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
        <GlassSurface
          state={state}
          reduceTransparency={reduceTransparency}
          style={[styles.focusExit, { top: insets.top + 10 }]}
        >
          <ChromeButton
            label="Exit Focus"
            symbol="xmark"
            state={state}
            showLabel
            onPress={() => onAction({ type: "exitFocus" })}
          />
        </GlassSurface>
        {!keyboardVisible && (
          <GlassSurface
            state={state}
            reduceTransparency={reduceTransparency}
            style={[styles.focusActions, { bottom: insets.bottom + 9 }]}
          >
            <ChromeButton
              label={focusRunning ? "Pause" : "Resume"}
              symbol={focusRunning ? "pause.fill" : "play.fill"}
              state={state}
              showLabel
              onPress={() => onAction({ type: focusRunning ? "pauseFocus" : "resumeFocus" })}
            />
            <View style={[styles.divider, { backgroundColor: alpha(state.colors.ink, 0.12) }]} />
            <ChromeButton
              label="End"
              symbol="stop.fill"
              state={state}
              showLabel
              onPress={() => onAction({ type: "endFocus" })}
            />
          </GlassSurface>
        )}
      </View>
    );
  }

  return (
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
      <GlassSurface
        state={state}
        reduceTransparency={reduceTransparency}
        style={[styles.headerCluster, { top: insets.top + 9 }]}
      >
        {!state.inRoom && (
          <ChromeButton
            label="Ask"
            symbol="sparkles"
            state={state}
            showLabel
            onPress={() => onAction({ type: "ask" })}
          />
        )}
        <ChromeButton label="Search" symbol="magnifyingglass" state={state} onPress={() => onAction({ type: "search" })} />
        <ChromeButton
          label="Filters"
          symbol="line.3.horizontal.decrease"
          state={state}
          badge={state.filtersActive}
          onPress={() => onAction({ type: "filters" })}
        />
        <ChromeButton
          label="Schedule"
          symbol="calendar.badge.clock"
          state={state}
          active={state.pathname === "/schedule"}
          onPress={() => onAction({ type: "navigate", url: "/schedule" })}
        />
        <ChromeButton
          label="Settings"
          symbol="gearshape"
          state={state}
          active={state.pathname === "/settings"}
          onPress={() => onAction({ type: "navigate", url: "/settings" })}
        />
      </GlassSurface>

      {!keyboardVisible && (
        <View pointerEvents="box-none" style={[styles.bottomRow, { bottom: insets.bottom + 9 }]}>
          <GlassSurface state={state} reduceTransparency={reduceTransparency} style={styles.tabBar}>
            {TABS.map((tab) => (
              <ChromeButton
                key={tab.url}
                label={tab.label}
                symbol={tab.symbol}
                state={state}
                active={state.pathname === tab.url}
                showLabel
                onPress={() => onAction({ type: "navigate", url: tab.url })}
              />
            ))}
          </GlassSurface>
          <GlassSurface
            state={state}
            reduceTransparency={reduceTransparency}
            tintColor={state.colors.accent}
            style={[styles.addButton, { borderColor: alpha(state.colors.accentInk, 0.18) }]}
          >
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Add item"
              onPress={() => onAction({ type: "compose" })}
              style={({ pressed }) => [styles.addPressable, pressed && styles.pressed]}
            >
              <SymbolView name="plus" size={24} weight="semibold" tintColor={state.colors.accentInk} />
            </Pressable>
          </GlassSurface>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  fallbackSurface: {
    borderWidth: StyleSheet.hairlineWidth,
    shadowColor: "#000",
    shadowOpacity: 0.24,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 9 },
  },
  pressed: {
    opacity: 0.62,
    transform: [{ scale: 0.96 }],
  },
  headerCluster: {
    position: "absolute",
    right: 12,
    minHeight: 48,
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 3,
    paddingVertical: 3,
    borderRadius: 25,
    overflow: "hidden",
  },
  chromeButton: {
    minWidth: 42,
    height: 42,
    paddingHorizontal: 9,
    borderRadius: 21,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 5,
  },
  chromeButtonLabelled: {
    minWidth: 52,
    paddingHorizontal: 10,
  },
  compactLabel: {
    fontSize: 12,
    lineHeight: 15,
    fontWeight: "600",
    letterSpacing: -0.1,
  },
  badge: {
    position: "absolute",
    width: 6,
    height: 6,
    borderRadius: 3,
    right: -2,
    top: -2,
  },
  bottomRow: {
    position: "absolute",
    left: 12,
    right: 12,
    height: 58,
    flexDirection: "row",
    gap: 10,
  },
  tabBar: {
    flex: 1,
    height: 58,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-around",
    paddingHorizontal: 4,
    borderRadius: 29,
    overflow: "hidden",
  },
  addButton: {
    width: 58,
    height: 58,
    borderRadius: 29,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: "hidden",
  },
  addPressable: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 29,
  },
  focusExit: {
    position: "absolute",
    right: 14,
    height: 46,
    borderRadius: 23,
    overflow: "hidden",
    paddingHorizontal: 2,
    paddingVertical: 2,
  },
  focusActions: {
    position: "absolute",
    left: "50%",
    width: 210,
    marginLeft: -105,
    height: 52,
    borderRadius: 26,
    overflow: "hidden",
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 4,
    paddingVertical: 3,
  },
  divider: {
    width: StyleSheet.hairlineWidth,
    height: 24,
  },
});
