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
  ): Promise<LiveActivityOperationResult>;
  endLive(kind: string): Promise<LiveActivityOperationResult>;
  updateLive(snapshot: string): Promise<LiveActivityOperationResult>;
  getLiveActivityStatus(): Promise<LiveActivityStatus>;
  startTestLiveActivity(): Promise<LiveActivityOperationResult>;
  stopAllLiveActivities(): Promise<LiveActivityOperationResult>;
  reconcileLiveActivities(snapshot: string | null): Promise<LiveActivityOperationResult>;
  readInbox(): string | null;
  clearInbox(): void;
};

export type LiveActivityResultCode =
  | "started"
  | "updated"
  | "ended"
  | "alreadyRunning"
  | "ready"
  | "activitiesDisabled"
  | "extensionMissing"
  | "notEligible"
  | "requestFailed"
  | "updateFailed"
  | "endFailed"
  | "unsupported"
  | "unknownError";

export type LiveActivityOperationResult = {
  success: boolean;
  code: LiveActivityResultCode;
  message: string;
  activityId?: string;
  activityState?: string;
  activeCount?: number;
  errorType?: string;
  operation?: string;
};

export type LiveActivityStatus = LiveActivityOperationResult & {
  supported: boolean;
  activitiesEnabled: boolean;
  activityIds: string[];
  activityStates: string[];
  extensionPresent: boolean;
  scheduleEligible: boolean;
  eligibilityReason: string;
  lastOperationCode?: string;
  lastOperationMessage?: string;
  lastErrorCode?: string | null;
  lastErrorMessage?: string | null;
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

export type DatebookModelPickerProps = ViewProps & {
  options: { id: string; label: string }[];
  selectedId: string;
  interfaceStyle?: DatebookInterfaceStyle;
  onSelect?: (event: { nativeEvent: { id: string } }) => void;
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

/** UIKit UIMenu model selector with real iOS 26 glass. */
export function requireDatebookModelPickerView() {
  try {
    return requireNativeViewManager<DatebookModelPickerProps>("DatebookNative", "DatebookModelPickerView");
  } catch {
    return null;
  }
}
