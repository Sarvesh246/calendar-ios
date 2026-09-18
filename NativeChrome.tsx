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
  Text,
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
    inkFaint?: string;
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
    inkFaint: "#858587",
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

const ASK_SLOT = 42;

function chromeColors(state: NativeChromeState) {
  return {
    ...state.colors,
    inkFaint: state.colors.inkFaint || state.colors.inkSoft,
  };
}

function alpha(hex: string, opacity: number) {
  const raw = hex.trim().replace("#", "");
  const expanded = raw.length === 3 ? raw.split("").map((part) => part + part).join("") : raw;
  if (!/^[0-9a-f]{6}$/i.test(expanded)) return `rgba(44, 44, 46, ${opacity})`;
  const value = Number.parseInt(expanded, 16);
  return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${opacity})`;
}

function tabProgress(selection: number, index: number) {
  return Math.max(0, 1 - Math.abs(selection - index));
}

function GlassSurface({
  children,
  state,
  reduceTransparency,
  style,
  tintColor,
  glassStyle = "regular",
  interactive = false,
  flat = false,
}: {
  children: ReactNode;
  state: NativeChromeState;
  reduceTransparency: boolean;
  style: ViewStyle | ViewStyle[];
  tintColor?: string;
  glassStyle?: "clear" | "regular" | "none";
  interactive?: boolean;
  flat?: boolean;
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
  const fill = !tintColor
    ? alpha(state.colors.surface, reduceTransparency ? 0.98 : 0.92)
    : tintColor.startsWith("rgb") || tintColor === "transparent"
      ? tintColor
      : alpha(tintColor, reduceTransparency ? 0.98 : 0.88);
  return (
    <View
      style={[
        style,
        !flat && styles.fallbackSurface,
        {
          backgroundColor: fill,
          borderColor: fill === "transparent" ? "transparent" : alpha(state.colors.ink, state.appearance === "dark" ? 0.16 : 0.1),
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
    return <GlassContainer spacing={18} style={style}>{children}</GlassContainer>;
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
  ink = false,
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
  ink?: boolean;
  onPress: () => void;
}) {
  const colors = chromeColors(state);
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
            tintColor={active ? state.colors.accent : ink ? state.colors.ink : colors.inkFaint}
          />
          {badge && <View style={[styles.badge, { backgroundColor: state.colors.accent }]} />}
        </View>
      </Pressable>
    </Animated.View>
  );
}

function TabItem({
  label,
  symbol,
  state,
  progress,
  onPress,
}: {
  label: string;
  symbol: SFSymbol;
  state: NativeChromeState;
  progress: number;
  onPress: () => void;
}) {
  const colors = chromeColors(state);
  const selected = progress > 0.5;

  return (
    <Pressable
      accessibilityRole="tab"
      accessibilityLabel={label}
      accessibilityState={{ selected }}
      onPress={onPress}
      style={styles.tabPressable}
    >
      <View style={styles.tabItemInner}>
        <SymbolView
          name={symbol}
          size={22}
          weight={selected ? "semibold" : "medium"}
          tintColor={selected ? state.colors.accent : colors.inkFaint}
        />
        <Text
          numberOfLines={1}
          allowFontScaling={false}
          style={[styles.tabLabel, { color: selected ? state.colors.ink : colors.inkFaint, fontWeight: selected ? "600" : "500" }]}
        >
          {label}
        </Text>
      </View>
    </Pressable>
  );
}

export function NativeChrome({ state, focusRunning, onAction }: Props) {
  const insets = useSafeAreaInsets();
  const [reduceTransparency, setReduceTransparency] = useState(false);
  const [reduceMotion, setReduceMotion] = useState(false);
  const [keyboardVisible, setKeyboardVisible] = useState(false);
  const [tabBarWidth, setTabBarWidth] = useState(0);
  const [selection, setSelection] = useState(0);
  const [dragging, setDragging] = useState(false);
  const indicatorX = useRef(new Animated.Value(0)).current;
  const askReveal = useRef(new Animated.Value(state.inRoom ? 0 : 1)).current;
  const dragOrigin = useRef(0);
  const dragPosition = useRef(0);
  const previewIndex = useRef(0);
  const lastTabIndex = useRef(0);
  const didDrag = useRef(false);
  const tapX = useRef(0);

  const segmentWidth = tabBarWidth > 0 ? tabBarWidth / TABS.length : 0;
  const routeIndex = TABS.findIndex((tab) => tab.url === state.pathname);
  const nativeGlass = Platform.OS === "ios" && isGlassEffectAPIAvailable() && !reduceTransparency;

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

  useEffect(() => {
    const id = indicatorX.addListener(({ value }) => {
      if (!segmentWidth) return;
      setSelection(value / segmentWidth);
    });
    return () => indicatorX.removeListener(id);
  }, [indicatorX, segmentWidth]);

  useEffect(() => {
    const open = state.inRoom ? 0 : 1;
    if (reduceMotion) {
      askReveal.setValue(open);
      return;
    }
    Animated.spring(askReveal, {
      toValue: open,
      stiffness: 380,
      damping: 34,
      mass: 0.72,
      useNativeDriver: false,
    }).start();
  }, [askReveal, reduceMotion, state.inRoom]);

  const settleIndicator = useCallback((index: number, velocity = 0) => {
    if (!segmentWidth) return;
    const target = index * segmentWidth;
    dragPosition.current = target;
    if (reduceMotion) {
      indicatorX.setValue(target);
      setSelection(index);
      return;
    }
    Animated.spring(indicatorX, {
      toValue: target,
      velocity,
      stiffness: 265,
      damping: 20,
      mass: 0.72,
      useNativeDriver: false,
    }).start();
  }, [indicatorX, reduceMotion, segmentWidth]);

  useEffect(() => {
    if (routeIndex < 0) {
      previewIndex.current = -1;
      setSelection(-1);
      return;
    }
    lastTabIndex.current = routeIndex;
    previewIndex.current = routeIndex;
    settleIndicator(routeIndex);
  }, [routeIndex, settleIndicator]);

  const navigateToTab = useCallback((index: number, velocity = 0) => {
    const tab = TABS[index];
    if (!tab) return;
    lastTabIndex.current = index;
    previewIndex.current = index;
    settleIndicator(index, velocity);
    if (state.pathname !== tab.url) onAction({ type: "navigate", url: tab.url });
  }, [onAction, settleIndicator, state.pathname]);

  const panResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => segmentWidth > 0,
    onMoveShouldSetPanResponder: (_, gesture) =>
      segmentWidth > 0 && Math.abs(gesture.dx) > Math.abs(gesture.dy),
    onMoveShouldSetPanResponderCapture: (_, gesture) =>
      segmentWidth > 0 && Math.abs(gesture.dx) > 6 && Math.abs(gesture.dx) > Math.abs(gesture.dy),
    onPanResponderTerminationRequest: () => false,
    onPanResponderGrant: (event) => {
      didDrag.current = false;
      tapX.current = event.nativeEvent.locationX;
      setDragging(true);
      indicatorX.stopAnimation((value) => {
        dragOrigin.current = value;
        dragPosition.current = value;
      });
    },
    onPanResponderMove: (_, gesture) => {
      if (Math.abs(gesture.dx) > 6) didDrag.current = true;
      const max = segmentWidth * (TABS.length - 1);
      const unbounded = dragOrigin.current + gesture.dx;
      const next = unbounded < 0
        ? unbounded * 0.28
        : unbounded > max
          ? max + (unbounded - max) * 0.28
          : unbounded;
      dragPosition.current = next;
      indicatorX.setValue(next);
      const nextIndex = Math.max(0, Math.min(TABS.length - 1, Math.round(next / segmentWidth)));
      if (nextIndex !== previewIndex.current) {
        previewIndex.current = nextIndex;
        void Haptics.selectionAsync();
      }
    },
    onPanResponderRelease: (_, gesture) => {
      setDragging(false);
      if (!segmentWidth) return;
      if (!didDrag.current) {
        const tapped = Math.max(0, Math.min(TABS.length - 1, Math.floor(tapX.current / segmentWidth)));
        if (tapped !== lastTabIndex.current) void Haptics.selectionAsync();
        navigateToTab(tapped, 0);
        return;
      }
      const max = segmentWidth * (TABS.length - 1);
      const projected = Math.max(0, Math.min(max, dragPosition.current + gesture.vx * 34));
      navigateToTab(Math.round(projected / segmentWidth), gesture.vx);
    },
    onPanResponderTerminate: () => {
      setDragging(false);
      settleIndicator(lastTabIndex.current);
    },
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
        <Animated.View
          pointerEvents={state.inRoom ? "none" : "auto"}
          style={{
            width: askReveal.interpolate({ inputRange: [0, 1], outputRange: [0, ASK_SLOT] }),
            opacity: askReveal,
            overflow: "hidden",
          }}
        >
          <ChromeButton label="Ask" symbol="sparkles" state={state} reduceMotion={reduceMotion} onPress={() => onAction({ type: "ask" })} />
        </Animated.View>
        <ChromeButton label="Search" symbol="magnifyingglass" state={state} reduceMotion={reduceMotion} onPress={() => onAction({ type: "search" })} />
        <ChromeButton label="Filters" symbol="line.3.horizontal.decrease" state={state} reduceMotion={reduceMotion} badge={state.filtersActive} onPress={() => onAction({ type: "filters" })} />
        <ChromeButton label="Schedule" symbol="calendar.badge.clock" state={state} reduceMotion={reduceMotion} active={state.pathname === "/schedule"} onPress={() => onAction({ type: "navigate", url: "/schedule" })} />
        <ChromeButton label="Settings" symbol="gearshape" state={state} reduceMotion={reduceMotion} active={state.pathname === "/settings"} onPress={() => onAction({ type: "navigate", url: "/settings" })} />
      </GlassSurface>

      {!keyboardVisible && (
        <View pointerEvents="box-none" style={[styles.dockWrap, { bottom: insets.bottom + 10 }]}>
          <View
            pointerEvents="none"
            style={[
              styles.dockGlow,
              {
                backgroundColor: alpha(state.colors.accent, state.appearance === "dark" ? 0.42 : 0.22),
                shadowColor: state.colors.accent,
              },
            ]}
          />
          <GlassGroup reduceTransparency={reduceTransparency} style={styles.dockStack}>
            <GlassSurface
              state={state}
              reduceTransparency={reduceTransparency}
              interactive
              glassStyle="regular"
              style={styles.tabCapsule}
            >
              <View
                accessibilityRole="tablist"
                style={styles.tabBarContents}
                onLayout={onTabBarLayout}
                {...panResponder.panHandlers}
              >
                {segmentWidth > 0 && selection >= 0 && (
                  <Animated.View
                    pointerEvents="none"
                    style={[
                      styles.selectedPillTrack,
                      { width: segmentWidth, transform: [{ translateX: indicatorX }] },
                    ]}
                  >
                    <View
                      style={[
                        styles.selectedPill,
                        {
                          transform: [{ scale: reduceMotion ? 1 : dragging ? 1.03 : 1 }],
                          backgroundColor: nativeGlass
                            ? alpha(state.colors.ink, state.appearance === "dark" ? 0.18 : 0.14)
                            : alpha(state.colors.surface, state.appearance === "dark" ? 0.94 : 0.98),
                          borderColor: alpha("#ffffff", state.appearance === "dark" ? 0.28 : 0.55),
                        },
                      ]}
                    >
                      <View style={[styles.selectedPillSheen, { backgroundColor: alpha("#ffffff", state.appearance === "dark" ? 0.28 : 0.62) }]} />
                    </View>
                  </Animated.View>
                )}
                {TABS.map((tab, index) => (
                  <TabItem
                    key={tab.url}
                    label={tab.label}
                    symbol={tab.symbol}
                    state={state}
                    progress={tabProgress(selection, index)}
                    onPress={() => {
                      if (index !== lastTabIndex.current) void Haptics.selectionAsync();
                      navigateToTab(index);
                    }}
                  />
                ))}
              </View>
            </GlassSurface>

            <GlassSurface
              state={state}
              reduceTransparency={reduceTransparency}
              interactive
              glassStyle="regular"
              style={styles.addButton}
            >
              <ChromeButton
                label="Add item"
                symbol="plus"
                state={state}
                reduceMotion={reduceMotion}
                ink
                large
                onPress={() => onAction({ type: "compose" })}
              />
            </GlassSurface>
          </GlassGroup>
        </View>
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
  dockWrap: {
    position: "absolute",
    left: 22,
    right: 22,
    alignItems: "center",
  },
  dockGlow: {
    position: "absolute",
    left: "12%",
    right: "12%",
    bottom: 4,
    height: 36,
    borderRadius: 36,
    opacity: 0.9,
    shadowOpacity: 0.55,
    shadowRadius: 28,
    shadowOffset: { width: 0, height: 10 },
  },
  dockStack: {
    flexDirection: "row",
    width: "100%",
    maxWidth: 420,
    alignItems: "stretch",
    gap: 10,
  },
  tabCapsule: {
    flex: 1,
    height: 62,
    borderRadius: 31,
    overflow: "hidden",
  },
  tabBarContents: {
    flex: 1,
    flexDirection: "row",
    alignItems: "stretch",
    padding: 4,
  },
  selectedPillTrack: {
    position: "absolute",
    top: 4,
    bottom: 4,
    left: 4,
  },
  selectedPill: {
    flex: 1,
    borderRadius: 24,
    overflow: "hidden",
    borderWidth: StyleSheet.hairlineWidth,
  },
  selectedPillSheen: {
    position: "absolute",
    left: 8,
    right: 8,
    top: 1,
    height: 10,
    borderRadius: 8,
    opacity: 0.7,
  },
  tabPressable: {
    flex: 1,
    minWidth: 0,
    minHeight: 48,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 4,
    zIndex: 1,
  },
  tabItemInner: {
    alignItems: "center",
    gap: 2,
  },
  tabLabel: {
    fontSize: 10.5,
    letterSpacing: 0.105,
    fontFamily: Platform.OS === "ios" ? "System" : undefined,
  },
  addButton: {
    width: 62,
    height: 62,
    borderRadius: 31,
    alignItems: "center",
    justifyContent: "center",
    overflow: "hidden",
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
