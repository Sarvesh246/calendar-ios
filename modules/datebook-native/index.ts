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
  /** The tab bar's real, currently-rendered height (a UITabBarController
   *  composes this itself — it isn't something the `style` height alone
   *  determines), fired whenever it changes. */
  onMeasuredHeight?: (event: { nativeEvent: { height: number } }) => void;
};

export type DatebookGlassButtonProps = ViewProps & {
  disabled?: boolean;
  accessibilityLabel?: string;
  interfaceStyle?: DatebookInterfaceStyle;
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

/** Real `UIButton.Configuration.glass()`-backed circular "+" control. */
export function requireDatebookGlassButtonView() {
  try {
    return requireNativeViewManager<DatebookGlassButtonProps>("DatebookNative", "DatebookGlassButtonView");
  } catch {
    return null;
  }
}
