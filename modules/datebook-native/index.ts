import { requireNativeModule, requireNativeViewManager } from "expo-modules-core";
import type { ViewProps } from "react-native";

type Native = {
  writeSnapshot(json: string): Promise<void>;
  indexSpotlight(json: string): Promise<void>;
  startLive(
    kind: string,
    id: string,
    title: string,
    subtitle: string,
    start: number,
    end: number,
    color: string,
    running: boolean
  ): Promise<void>;
  endLive(kind: string): Promise<void>;
  readInbox(): string | null;
  clearInbox(): void;
};

export function datebookNative(): Native | null {
  try {
    return requireNativeModule<Native>("DatebookNative");
  } catch {
    return null;
  }
}

export type DatebookTabBarItem = { label: string; symbol: string; url: string };

/** Datebook's own resolved in-app appearance — never the phone's Dark Mode
 *  setting, which the view would otherwise inherit by default. */
export type DatebookInterfaceStyle = "light" | "dark";

export type DatebookTabBarProps = ViewProps & {
  items: DatebookTabBarItem[];
  selectedIndex: number;
  tintColor?: string;
  unselectedTintColor?: string;
  disabled?: boolean;
  interfaceStyle?: DatebookInterfaceStyle;
  onSelect?: (event: { nativeEvent: { index: number } }) => void;
};

/** One entry in the shared Ask/Search/Filters/Schedule/Settings glass pill.
 *  Boolean-ish fields are passed as "1"/"" (Expo's Prop bridge is simplest
 *  and most reliably typed as a flat `[String: String]`, matching the tab
 *  bar's own `items` prop above) rather than real booleans. */
export type DatebookGlassBarItem = {
  id: string;
  symbol: string;
  label: string;
  active?: "1" | "";
  accent?: "1" | "";
  badge?: "1" | "";
  /** "0" collapses the button to zero width with a spring, same as the old
   *  RN `askReveal` interpolation — everything else should pass "1". */
  visible?: "1" | "0";
};

export type DatebookGlassBarProps = ViewProps & {
  items: DatebookGlassBarItem[];
  tintColor?: string;
  disabled?: boolean;
  interfaceStyle?: DatebookInterfaceStyle;
  onPress?: (event: { nativeEvent: { id: string } }) => void;
};

export type DatebookGlassButtonProps = ViewProps & {
  disabled?: boolean;
  accessibilityLabel?: string;
  interfaceStyle?: DatebookInterfaceStyle;
  /** A constant accent tint on the glass itself (not just on press) — an
   *  explicit design choice, which is what justifies `.prominentGlass()`
   *  over plain `.glass()` on the native side. */
  tintColor?: string;
  /** The plus icon's color, read against `tintColor` — pass the theme's
   *  on-accent ink color, not a fixed light/dark value. */
  foregroundColor?: string;
  onPress?: (event: { nativeEvent: Record<string, never> }) => void;
};

/** Real `UITabBar`-backed three-item tray. Falls back to `null` off-iOS. */
export function requireDatebookTabBarView() {
  try {
    return requireNativeViewManager<DatebookTabBarProps>("DatebookNative", "DatebookTabBarView");
  } catch {
    return null;
  }
}

/** Real per-button `UIButton.Configuration.glass()` header pill (Ask/Search/
 *  Filters/Schedule/Settings) — deliberately not a `UITabBar`. */
export function requireDatebookGlassBarView() {
  try {
    return requireNativeViewManager<DatebookGlassBarProps>("DatebookNative", "DatebookGlassBarView");
  } catch {
    return null;
  }
}

/** Real `UIButton.Configuration.glass()`-backed circular "+" control. */
export function requireDatebookGlassButtonView() {
  try {
    return requireNativeViewManager<DatebookGlassButtonProps>("DatebookNative", "DatebookGlassButtonView");
  } catch {
    return null;
  }
}
