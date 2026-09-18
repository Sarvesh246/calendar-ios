import { GlassContainer, GlassView, isGlassEffectAPIAvailable } from "expo-glass-effect";
import * as Haptics from "expo-haptics";
import { SymbolView, type SFSymbol } from "expo-symbols";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  AccessibilityInfo,
  Animated,
  Keyboard,
  PanResponder,
  Platform,
  Pressable,
  StyleSheet,
  View,
  type LayoutChangeEvent,
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
  glassStyle = "regular",
  interactive = false,
}: {
  children: ReactNode;
  state: NativeChromeState;
  reduceTransparency: boolean;
  style: ViewStyle | ViewStyle[];
  tintColor?: string;
  glassStyle?: "clear" | "regular";
  interactive?: boolean;
}) {
  const nativeGlass = Platform.OS === "ios" && isGlassEffectAPIAvailable() && !reduceTransparency;
  if (nativeGlass) {
    return (
      <GlassView
        colorScheme={state.appearance}
        glassEffectStyle={glassStyle}
        tintColor={tintColor}
        isInteractive={interactive}
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
          backgroundColor: tintColor
            ? alpha(tintColor, reduceTransparency ? 0.98 : 0.88)
            : alpha(state.colors.surface, reduceTransparency ? 0.98 : 0.92),
          borderColor: alpha(state.colors.ink, state.appearance === "dark" ? 0.16 : 0.1),
        },
      ]}
    >
      {children}
    </View>
  );
}

function GlassGroup({ children, reduceTransparency, style }: {
  children: ReactNode;
  reduceTransparency: boolean;
  style: ViewStyle | ViewStyle[];
}) {
  const nativeGlass = Platform.OS === "ios" && isGlassEffectAPIAvailable() && !reduceTransparency;
  if (nativeGlass) {
    return <GlassContainer spacing={12} style={style}>{children}</GlassContainer>;
  }
  return <View style={style}>{children}</View>;
}

function ChromeButton({
  label,
  symbol,
  state,
  reduceMotion,
  active = false,
  highlightActive = true,
  badge = false,
  large = false,
  onPress,
}: {
  label: string;
  symbol: SFSymbol;
  state: NativeChromeState;
  reduceMotion: boolean;
  active?: boolean;
  highlightActive?: boolean;
  badge?: boolean;
  large?: boolean;
  onPress: () => void;
}) {
  const scale = useRef(new Animated.Value(1)).current;
  const springTo = (toValue: number) => {
    if (reduceMotion) {
      scale.setValue(1);
      return;
    }
    Animated.spring(scale, {
      toValue,
      stiffness: toValue < 1 ? 380 : 235,
      damping: toValue < 1 ? 26 : 13,
      mass: 0.65,
      useNativeDriver: true,
    }).start();
  };

  return (
    <Animated.View style={{ transform: [{ scale }] }}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={label}
        accessibilityState={{ selected: active }}
        hitSlop={5}
        onPress={onPress}
        onPressIn={() => springTo(0.9)}
        onPressOut={() => springTo(1)}
        style={[
          styles.chromeButton,
          large && styles.largeChromeButton,
          active && highlightActive && { backgroundColor: alpha(state.colors.accent, state.appearance === "dark" ? 0.18 : 0.11) },
        ]}
      >
        <View>
          <SymbolView
            name={symbol}
            size={large ? 22 : 18}
            weight={active ? "semibold" : "medium"}
            tintColor={active ? state.colors.accent : state.colors.inkSoft}
          />
          {badge && <View style={[styles.badge, { backgroundColor: state.colors.accent }]} />}
        </View>
      </Pressable>
    </Animated.View>
  );
}

export function NativeChrome({ state, focusRunning, onAction }: Props) {
  const insets = useSafeAreaInsets();
  const [reduceTransparency, setReduceTransparency] = useState(false);
  const [reduceMotion, setReduceMotion] = useState(false);
  const [keyboardVisible, setKeyboardVisible] = useState(false);
  const [tabBarWidth, setTabBarWidth] = useState(0);
  const indicatorX = useRef(new Animated.Value(0)).current;
  const dragOrigin = useRef(0);
  const dragPosition = useRef(0);
  const previewIndex = useRef(0);
  const lastTabIndex = useRef(0);

  const segmentWidth = tabBarWidth > 0 ? tabBarWidth / TABS.length : 0;
  const routeIndex = TABS.findIndex((tab) => tab.url === state.pathname);

  useEffect(() => {
    void AccessibilityInfo.isReduceTransparencyEnabled().then(setReduceTransparency);
    void AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const transparencySub = AccessibilityInfo.addEventListener("reduceTransparencyChanged", setReduceTransparency);
    const motionSub = AccessibilityInfo.addEventListener("reduceMotionChanged", setReduceMotion);
    return () => {
      transparencySub.remove();
      motionSub.remove();
    };
  }, []);

  useEffect(() => {
    const show = Keyboard.addListener("keyboardWillShow", () => setKeyboardVisible(true));
    const hide = Keyboard.addListener("keyboardWillHide", () => setKeyboardVisible(false));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);

  const settleIndicator = useCallback((index: number, velocity = 0) => {
    if (!segmentWidth) return;
    const target = index * segmentWidth;
    dragPosition.current = target;
    if (reduceMotion) {
      indicatorX.setValue(target);
      return;
    }
    Animated.spring(indicatorX, {
      toValue: target,
      velocity,
      stiffness: 265,
      damping: 20,
      mass: 0.72,
      useNativeDriver: true,
    }).start();
  }, [indicatorX, reduceMotion, segmentWidth]);

  useEffect(() => {
    if (routeIndex < 0) return;
    lastTabIndex.current = routeIndex;
    previewIndex.current = routeIndex;
    settleIndicator(routeIndex);
  }, [routeIndex, settleIndicator]);

  const navigateToTab = useCallback((index: number) => {
    const tab = TABS[index];
    if (!tab) return;
    lastTabIndex.current = index;
    previewIndex.current = index;
    settleIndicator(index);
    if (state.pathname !== tab.url) onAction({ type: "navigate", url: tab.url });
  }, [onAction, settleIndicator, state.pathname]);

  const panResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => false,
    onMoveShouldSetPanResponder: (_, gesture) =>
      segmentWidth > 0 && Math.abs(gesture.dx) > 5 && Math.abs(gesture.dx) > Math.abs(gesture.dy),
    onMoveShouldSetPanResponderCapture: (_, gesture) =>
      segmentWidth > 0 && Math.abs(gesture.dx) > 5 && Math.abs(gesture.dx) > Math.abs(gesture.dy),
    onPanResponderGrant: () => {
      indicatorX.stopAnimation((value) => {
        dragOrigin.current = value;
        dragPosition.current = value;
      });
    },
    onPanResponderMove: (_, gesture) => {
      const max = segmentWidth * (TABS.length - 1);
      const next = Math.max(0, Math.min(max, dragOrigin.current + gesture.dx));
      dragPosition.current = next;
      indicatorX.setValue(next);
      const nextIndex = Math.round(next / segmentWidth);
      if (nextIndex !== previewIndex.current) {
        previewIndex.current = nextIndex;
        void Haptics.selectionAsync();
      }
    },
    onPanResponderRelease: (_, gesture) => {
      const max = segmentWidth * (TABS.length - 1);
      const projected = Math.max(0, Math.min(max, dragPosition.current + gesture.vx * 34));
      navigateToTab(Math.round(projected / segmentWidth));
    },
    onPanResponderTerminate: () => settleIndicator(lastTabIndex.current),
  }), [indicatorX, navigateToTab, segmentWidth, settleIndicator]);

  const onTabBarLayout = (event: LayoutChangeEvent) => setTabBarWidth(event.nativeEvent.layout.width);

  if (!state.ready || state.obscured) return null;

  if (state.focusMode) {
    return (
      <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
        <GlassSurface state={state} reduceTransparency={reduceTransparency} interactive glassStyle="clear" style={[styles.focusExit, { top: insets.top + 10 }]}>
          <ChromeButton label="Exit Focus" symbol="xmark" state={state} reduceMotion={reduceMotion} onPress={() => onAction({ type: "exitFocus" })} />
        </GlassSurface>
        {!keyboardVisible && (
          <GlassSurface state={state} reduceTransparency={reduceTransparency} interactive style={[styles.focusActions, { bottom: insets.bottom + 9 }]}>
            <ChromeButton label={focusRunning ? "Pause" : "Resume"} symbol={focusRunning ? "pause.fill" : "play.fill"} state={state} reduceMotion={reduceMotion} large onPress={() => onAction({ type: focusRunning ? "pauseFocus" : "resumeFocus" })} />
            <View style={[styles.divider, { backgroundColor: alpha(state.colors.ink, 0.12) }]} />
            <ChromeButton label="End Focus" symbol="stop.fill" state={state} reduceMotion={reduceMotion} large onPress={() => onAction({ type: "endFocus" })} />
          </GlassSurface>
        )}
      </View>
    );
  }

  return (
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
      <GlassSurface state={state} reduceTransparency={reduceTransparency} interactive glassStyle="clear" style={[styles.headerCluster, { top: insets.top + 9 }]}>
        {!state.inRoom && <ChromeButton label="Ask" symbol="sparkles" state={state} reduceMotion={reduceMotion} onPress={() => onAction({ type: "ask" })} />}
        <ChromeButton label="Search" symbol="magnifyingglass" state={state} reduceMotion={reduceMotion} onPress={() => onAction({ type: "search" })} />
        <ChromeButton label="Filters" symbol="line.3.horizontal.decrease" state={state} reduceMotion={reduceMotion} badge={state.filtersActive} onPress={() => onAction({ type: "filters" })} />
        <ChromeButton label="Schedule" symbol="calendar.badge.clock" state={state} reduceMotion={reduceMotion} active={state.pathname === "/schedule"} onPress={() => onAction({ type: "navigate", url: "/schedule" })} />
        <ChromeButton label="Settings" symbol="gearshape" state={state} reduceMotion={reduceMotion} active={state.pathname === "/settings"} onPress={() => onAction({ type: "navigate", url: "/settings" })} />
      </GlassSurface>

      {!keyboardVisible && (
        <GlassGroup reduceTransparency={reduceTransparency} style={[styles.bottomRow, { bottom: insets.bottom + 9 }]}>
          <GlassSurface state={state} reduceTransparency={reduceTransparency} interactive style={styles.tabBar}>
            <View style={styles.tabBarContents} onLayout={onTabBarLayout} {...panResponder.panHandlers}>
              {segmentWidth > 0 && (
                <Animated.View pointerEvents="none" style={[styles.indicatorFrame, { width: segmentWidth, transform: [{ translateX: indicatorX }] }]}>
                  <GlassSurface state={state} reduceTransparency={reduceTransparency} glassStyle="clear" tintColor={alpha(state.colors.accent, state.appearance === "dark" ? 0.42 : 0.28)} style={styles.activeIndicator}>
                    <View />
                  </GlassSurface>
                </Animated.View>
              )}
              {TABS.map((tab, index) => (
                <View key={tab.url} style={styles.tabSlot}>
                  <ChromeButton label={tab.label} symbol={tab.symbol} state={state} reduceMotion={reduceMotion} active={routeIndex === index} highlightActive={false} large onPress={() => navigateToTab(index)} />
                </View>
              ))}
            </View>
          </GlassSurface>

          <GlassSurface state={state} reduceTransparency={reduceTransparency} interactive tintColor={state.colors.accent} style={[styles.addButton, { backgroundColor: alpha(state.colors.accent, 0.42), borderColor: alpha(state.colors.accentInk, 0.24), shadowColor: state.colors.accent }]}>
            <ChromeButton label="Add item" symbol="plus" state={{ ...state, colors: { ...state.colors, inkSoft: state.colors.accentInk } }} reduceMotion={reduceMotion} large onPress={() => onAction({ type: "compose" })} />
          </GlassSurface>
        </GlassGroup>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  fallbackSurface: {
    borderWidth: StyleSheet.hairlineWidth,
    shadowColor: "#000",
    shadowOpacity: 0.22,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 9 },
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
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: "center",
    justifyContent: "center",
  },
  largeChromeButton: {
    width: 50,
    height: 50,
    borderRadius: 25,
  },
  badge: {
    position: "absolute",
    width: 6,
    height: 6,
    borderRadius: 3,
    right: -3,
    top: -3,
  },
  bottomRow: {
    position: "absolute",
    left: 12,
    right: 12,
    height: 60,
    flexDirection: "row",
    gap: 10,
  },
  tabBar: {
    flex: 1,
    height: 60,
    borderRadius: 30,
    overflow: "hidden",
  },
  tabBarContents: {
    flex: 1,
    margin: 4,
    flexDirection: "row",
    alignItems: "center",
  },
  tabSlot: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    zIndex: 2,
  },
  indicatorFrame: {
    position: "absolute",
    left: 0,
    top: 0,
    bottom: 0,
    paddingHorizontal: 2,
  },
  activeIndicator: {
    flex: 1,
    borderRadius: 26,
    overflow: "hidden",
  },
  addButton: {
    width: 60,
    height: 60,
    borderRadius: 30,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: "center",
    justifyContent: "center",
    overflow: "hidden",
    shadowOpacity: 0.34,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 8 },
  },
  focusExit: {
    position: "absolute",
    right: 14,
    width: 48,
    height: 48,
    borderRadius: 24,
    overflow: "hidden",
    alignItems: "center",
    justifyContent: "center",
  },
  focusActions: {
    position: "absolute",
    left: "50%",
    width: 126,
    marginLeft: -63,
    height: 58,
    borderRadius: 29,
    overflow: "hidden",
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-around",
    paddingHorizontal: 6,
  },
  divider: {
    width: StyleSheet.hairlineWidth,
    height: 25,
  },
});
