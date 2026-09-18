import { requireNativeModule } from "expo-modules-core";

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
