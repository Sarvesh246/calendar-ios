import { GlassView, isGlassEffectAPIAvailable } from "expo-glass-effect";
import { SymbolView, type SFSymbol } from "expo-symbols";
import { requireDatebookGlassButtonView, requireDatebookTabBarView } from "./modules/datebook-native";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import {
  AccessibilityInfo,
  Animated,
  Keyboard,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
  type ViewStyle,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

// Real `UITabBar` / `UIButton.Configuration.glass()` on iOS; `null` on other
// platforms (or an Expo Go client without the custom native module), where a
// plain JS fallback below takes over. Resolved once at module scope, not
// per-render.
const DatebookNativeTabBar = requireDatebookTabBarView();
const DatebookNativeGlassButton = requireDatebookGlassButtonView();

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

// RN layout height/width given to each native control (their styles below
// just reference these). DatebookTabBarView.swift now embeds a real
// UITabBarController rather than a bare UITabBar — a bare bar's own
// background rendered at a fixed, content-hugging height no matter how it
// was framed or sized, and a wrapping second glass view grew it but caused
// illegal glass-in-glass nesting artifacts. A UITabBarController needs
// real room above its bar for the (invisible, unused) content area its own
// layout expects, so its native view is deliberately taller than the
// visible dock and overflows upward — see TRAY_TOUCH_AREA_HEIGHT and
// `tabBarNative` below. `tabBarSlot` keeps the pre-existing normal-flow
// footprint so this doesn't shift the "+" button's position.
const TRAY_HEIGHT = 64;
const TRAY_TOUCH_AREA_HEIGHT = 160;
const ADD_BUTTON_SIZE = 64;

// The theme's own ink/inkFaint are tuned for AA contrast on a flat card
// surface, not on frosted glass sitting over whatever content is scrolling
// underneath it. Chrome glyphs need their own fixed, always-legible neutrals
// — dark charcoal in light mode, near-white in dark mode — independent of
// how washed-out a given theme's faint tone happens to be. Accent still
// comes from the theme so the bar stays on-brand per app theme.
function chromeNeutral(state: NativeChromeState) {
  const dark = state.appearance === "dark";
  return {
    ink: dark ? "#f5f5f7" : "#1c1c1e",
    faint: dark ? "rgba(245, 245, 247, 0.86)" : "rgba(28, 28, 30, 0.68)",
  };
}

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
  accent = false,
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
  accent?: boolean;
  onPress: () => void;
}) {
  const neutral = chromeNeutral(state);
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
          (accent || (active && highlightActive)) && {
            backgroundColor: alpha(state.colors.accent, state.appearance === "dark" ? 0.2 : 0.13),
          },
        ]}
      >
        <View>
          <SymbolView
            name={symbol}
            size={large ? 22 : 18}
            weight={active || accent ? "semibold" : "medium"}
            tintColor={active || accent ? state.colors.accent : ink ? neutral.ink : neutral.faint}
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
  selected,
  onPress,
}: {
  label: string;
  symbol: SFSymbol;
  state: NativeChromeState;
  selected: boolean;
  onPress: () => void;
}) {
  const neutral = chromeNeutral(state);
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
          tintColor={selected ? state.colors.accent : neutral.faint}
        />
        <Text
          numberOfLines={1}
          allowFontScaling={false}
          style={[
            styles.tabLabel,
            {
              color: selected ? state.colors.accent : neutral.faint,
              fontWeight: selected ? "600" : "500",
            },
          ]}
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
  // The tab bar's real rendered height is composed by UITabBarController
  // itself, not decided by the `style` height React gives it — so the "+"
  // button is sized off the measured value the native view reports back,
  // falling back to ADD_BUTTON_SIZE until the first measurement arrives.
  const [measuredTrayHeight, setMeasuredTrayHeight] = useState(ADD_BUTTON_SIZE);
  const askReveal = useRef(new Animated.Value(state.inRoom ? 0 : 1)).current;

  // -1 means the current route has no matching tab (Settings/Schedule):
  // leave the tray without a lit destination rather than forcing one.
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

  // The native UITabBar owns press-and-hold lift, finger tracking between
  // items, accent preview, spring settle and haptics itself — this only
  // relays the committed selection into the same navigate intent the old
  // custom pill used to send. Setting `selectedIndex` from a route change
  // (below, via the `routeIndex` prop) never re-enters here: iOS only calls
  // a tab bar's delegate for a user-driven selection, not a programmatic one.
  const navigateToTab = useCallback((index: number) => {
    const tab = TABS[index];
    if (!tab) return;
    if (state.pathname !== tab.url) onAction({ type: "navigate", url: tab.url });
  }, [onAction, state.pathname]);

  if (!state.ready || state.obscured) return null;

  if (state.focusMode) {
    return (
      <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
        <GlassSurface state={state} reduceTransparency={reduceTransparency} glassStyle="clear" style={[styles.focusExit, { top: insets.top + 10 }]}>
          <ChromeButton label="Exit Focus" symbol="xmark" state={state} reduceMotion={reduceMotion} onPress={() => onAction({ type: "exitFocus" })} />
        </GlassSurface>
        {!keyboardVisible && (
          <GlassSurface state={state} reduceTransparency={reduceTransparency} style={[styles.focusActions, { bottom: insets.bottom + 9 }]}>
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
      <GlassSurface state={state} reduceTransparency={reduceTransparency} glassStyle="regular" tintColor={state.colors.surface} style={[styles.headerCluster, { top: insets.top + 9 }]}>
        <Animated.View
          pointerEvents={state.inRoom ? "none" : "auto"}
          style={{
            width: askReveal.interpolate({ inputRange: [0, 1], outputRange: [0, ASK_SLOT] }),
            opacity: askReveal,
            overflow: "hidden",
            borderRadius: ASK_SLOT / 2,
          }}
        >
          <ChromeButton label="Ask" symbol="sparkles" state={state} reduceMotion={reduceMotion} accent onPress={() => onAction({ type: "ask" })} />
        </Animated.View>
        <ChromeButton label="Search" symbol="magnifyingglass" state={state} reduceMotion={reduceMotion} onPress={() => onAction({ type: "search" })} />
        <ChromeButton label="Filters" symbol="line.3.horizontal.decrease" state={state} reduceMotion={reduceMotion} badge={state.filtersActive} onPress={() => onAction({ type: "filters" })} />
        <ChromeButton label="Schedule" symbol="calendar.badge.clock" state={state} reduceMotion={reduceMotion} active={state.pathname === "/schedule"} onPress={() => onAction({ type: "navigate", url: "/schedule" })} />
        <ChromeButton label="Settings" symbol="gearshape" state={state} reduceMotion={reduceMotion} active={state.pathname === "/settings"} onPress={() => onAction({ type: "navigate", url: "/settings" })} />
      </GlassSurface>

      {!keyboardVisible && (
        <View
          pointerEvents="box-none"
          style={[
            styles.dockWrap,
            {
              // A single shared offset for the whole dock (tray + button
              // together), not a per-control adjustment, so they stay
              // exactly aligned with each other.
              bottom: insets.bottom + 1,
              left: Math.max(12, insets.left + 8),
              right: Math.max(12, insets.right + 8),
            },
          ]}
        >
          {/* Two separate system glass objects, kept apart by this row gap —
              never merged into one droplet. Each is a real UIKit control
              (UITabBar / UIButton.Configuration.glass()) on iOS; UIKit owns
              all press, drag, refraction and spring behavior for both. */}
          <View style={[styles.dockRow, { height: Math.max(TRAY_HEIGHT, measuredTrayHeight) }]}>
            {DatebookNativeTabBar ? (
              // A UITabBarController-embedded tab bar renders its taller,
              // properly-proportioned floating treatment only when given
              // real room above the bar for the (invisible, unused) content
              // area a controller expects — a bare UITabBar's own
              // background never grew past its default height no matter
              // how it was framed. `tabBarSlot` keeps the normal-flow
              // footprint (so the "+" button's position/gap don't move);
              // the native view itself overflows upward out of that slot,
              // and its own `hitTest` restricts real touches to the bar's
              // visible frame so the extra transparent space above it
              // still passes taps through to the page content.
              <View style={styles.tabBarSlot}>
                <DatebookNativeTabBar
                  accessibilityRole="tablist"
                  style={styles.tabBarNative}
                  items={TABS.map((tab) => ({ label: tab.label, symbol: tab.symbol, url: tab.url }))}
                  selectedIndex={routeIndex}
                  tintColor={state.colors.accent}
                  interfaceStyle={state.appearance}
                  disabled={false}
                  onSelect={(event) => navigateToTab(event.nativeEvent.index)}
                  onMeasuredHeight={(event) => setMeasuredTrayHeight(event.nativeEvent.height)}
                />
              </View>
            ) : (
              // Non-iOS (e.g. Android) or a client without the native module:
              // a plain JS row with no drag physics to fake. Liquid Glass is
              // an iOS-only ask; this path exists so the app still functions.
              <View accessibilityRole="tablist" style={styles.tabBarFallback}>
                {TABS.map((tab, index) => (
                  <TabItem
                    key={tab.url}
                    label={tab.label}
                    symbol={tab.symbol}
                    state={state}
                    selected={routeIndex === index}
                    onPress={() => navigateToTab(index)}
                  />
                ))}
              </View>
            )}

            {DatebookNativeGlassButton ? (
              // Sized to match the tab bar's actual measured height (a
              // UIButton, unlike UITabBar, does stretch to fill whatever
              // frame it's given, so this is a plain size — no equivalent
              // workaround needed on this side) — kept as a wholly separate
              // control, just made uniform with the tray beside it.
              <DatebookNativeGlassButton
                style={[styles.addButtonNative, { width: measuredTrayHeight, height: measuredTrayHeight }]}
                accessibilityLabel="Add item"
                interfaceStyle={state.appearance}
                disabled={false}
                onPress={() => onAction({ type: "compose" })}
              />
            ) : (
              <ChromeButton
                label="Add item"
                symbol="plus"
                state={state}
                reduceMotion={reduceMotion}
                ink
                large
                onPress={() => onAction({ type: "compose" })}
              />
            )}
          </View>
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
    zIndex: 40,
    elevation: 40,
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
    // Deliberately not clipped: a native UITabBar's pressed selection glass
    // and a UIButton's glass press both need room to lift/stretch outside
    // their resting bounds.
    position: "absolute",
    alignItems: "center",
    zIndex: 40,
    elevation: 40,
  },
  dockRow: {
    width: "100%",
    maxWidth: 420,
    // Height comes from the render call (Math.max(TRAY_HEIGHT,
    // measuredTrayHeight)) since the real tray height is only known once
    // the native view reports it; this is just a sane pre-measurement
    // fallback.
    height: TRAY_HEIGHT,
    flexDirection: "row",
    // Center rather than stretch: the tray and the "+" button are
    // deliberately different heights now, so each keeps its own real size
    // and both sit centered on the same row instead of one stretching to
    // match the other.
    alignItems: "center",
    gap: 12,
  },
  tabBarSlot: {
    // Normal-flow spacer matching the tray's pre-existing footprint, so
    // the "+" button's position and the row/dock gap don't move — the
    // actual native view (below) overflows upward out of this slot.
    flex: 1,
    height: TRAY_HEIGHT,
  },
  tabBarNative: {
    position: "absolute",
    left: 0,
    right: 0,
    bottom: 0,
    height: TRAY_TOUCH_AREA_HEIGHT,
  },
  tabBarFallback: {
    flex: 1,
    height: TRAY_HEIGHT,
    borderRadius: TRAY_HEIGHT / 2,
    flexDirection: "row",
    alignItems: "stretch",
    padding: 4,
    overflow: "hidden",
    backgroundColor: "rgba(44, 44, 46, 0.92)",
  },
  tabPressable: {
    flex: 1,
    minWidth: 0,
    minHeight: 48,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 4,
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
  addButtonNative: {
    // Fallback size until the first onMeasuredHeight event arrives (the
    // render call overrides width/height with the measured tray height);
    // width equal to height keeps it a true circle either way.
    width: ADD_BUTTON_SIZE,
    height: ADD_BUTTON_SIZE,
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
    zIndex: 40,
    elevation: 40,
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
    zIndex: 40,
    elevation: 40,
  },
  divider: {
    width: StyleSheet.hairlineWidth,
    height: 25,
  },
});
