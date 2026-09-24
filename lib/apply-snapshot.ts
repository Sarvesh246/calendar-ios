import * as Notifications from "expo-notifications";
import * as Calendar from "expo-calendar";
import * as Location from "expo-location";
import * as BackgroundFetch from "expo-background-fetch";
import * as TaskManager from "expo-task-manager";
import * as Linking from "expo-linking";
import { datebookNative } from "../modules/datebook-native";
import type { LiveActivityOperationResult } from "../modules/datebook-native";
import type { NativeSnapshot } from "./snapshot-types";

const BG_TASK = "datebook-refresh";
const CAL_NAME = "Datebook";

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

export async function requestNativeNotifications(): Promise<boolean> {
  const { status } = await Notifications.requestPermissionsAsync();
  try {
    await Notifications.setNotificationCategoryAsync("DATEBOOK_REMINDER", [
      { identifier: "COMPLETE", buttonTitle: "Complete", options: { isDestructive: false, opensAppToForeground: true } },
      { identifier: "SNOOZE", buttonTitle: "Snooze 15 min", options: { opensAppToForeground: true } },
    ]);
  } catch {
    /* already registered */
  }
  return status === "granted";
}

let lastLiveActivityResult: LiveActivityOperationResult | null = null;

export function getLastLiveActivityResult() {
  return lastLiveActivityResult;
}

export async function applySnapshot(snapshot: NativeSnapshot): Promise<LiveActivityOperationResult | null> {
  const native = datebookNative();
  await native?.writeSnapshot(JSON.stringify(snapshot));
  await native?.indexSpotlight(JSON.stringify(snapshot.spotlight ?? []));
  await Notifications.setBadgeCountAsync(Math.max(0, snapshot.badge ?? 0));
  await scheduleReminders(snapshot);
  const liveResult = await syncLive(snapshot);
  // Apple Calendar mirroring is optional; a failure there must not surface as
  // the Live Activity status or stop background registration.
  if (snapshot.appleCalendarSync) {
    try {
      await upsertCalendar(snapshot);
    } catch (error) {
      console.warn("[Datebook] Apple Calendar sync failed", error);
    }
  }
  await registerBackground();
  return liveResult;
}

async function scheduleReminders(snapshot: NativeSnapshot) {
  await Notifications.cancelAllScheduledNotificationsAsync();
  for (const r of snapshot.reminders ?? []) {
    const content: Notifications.NotificationContentInput = {
      title: r.title,
      body: r.body,
      sound: r.kind === "class" ? "default" : "default",
      categoryIdentifier: "DATEBOOK_REMINDER",
      data: { itemId: r.itemId, kind: r.kind },
    };
    if (r.kind === "location" && r.place) {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== "granted") continue;
      await Location.requestBackgroundPermissionsAsync();
      try {
        await Notifications.scheduleNotificationAsync({
          identifier: r.id.slice(0, 64),
          content,
          trigger: {
            type: "location",
            region: {
              identifier: r.id.slice(0, 64),
              latitude: r.place.lat,
              longitude: r.place.lng,
              radius: r.place.radiusMeters,
              notifyOnEnter: true,
              notifyOnExit: false,
            },
          } as never,
        });
      } catch {
        /* Always-location not granted yet */
      }
      continue;
    }
    if (!r.fireAt) continue;
    const when = new Date(r.fireAt);
    if (when.getTime() <= Date.now() + 2000) continue;
    await Notifications.scheduleNotificationAsync({
      identifier: r.id.slice(0, 64),
      content,
      trigger: {
        type: Notifications.SchedulableTriggerInputTypes.DATE,
        date: when,
      },
    });
  }
}

async function syncLive(snapshot: NativeSnapshot): Promise<LiveActivityOperationResult | null> {
  const native = datebookNative();
  if (!native) {
    lastLiveActivityResult = {
      success: false,
      code: "unsupported",
      message: "The Datebook native module is unavailable.",
      operation: "reconcile",
    };
    return lastLiveActivityResult;
  }
  try {
    const result = await native.reconcileLiveActivities(JSON.stringify(snapshot.liveActivity));
    lastLiveActivityResult = result;
    if (!result.success) {
      console.warn(`[Datebook Live Activity] ${result.code}: ${result.message}`);
    }
    return result;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    lastLiveActivityResult = {
      success: false,
      code: "unknownError",
      message: `Live Activity reconciliation failed: ${message}`,
      operation: "reconcile",
    };
    console.error("[Datebook Live Activity] reconciliation threw", error);
    return lastLiveActivityResult;
  }
}

async function upsertCalendar(snapshot: NativeSnapshot) {
  const perm = await Calendar.requestCalendarPermissions();
  if (perm.status !== "granted") return;
  const calendars = await Calendar.getCalendars(Calendar.EntityTypes.EVENT);
  let calendar = calendars.find((c) => c.title === CAL_NAME && c.allowsModifications);
  if (!calendar) {
    const source =
      calendars.find((c) => c.source?.name === "Default")?.source ??
      calendars.find((c) => c.allowsModifications)?.source;
    if (!source) return;
    calendar = await Calendar.createCalendar({
      title: CAL_NAME,
      color: "#0A84FF",
      entityType: Calendar.EntityTypes.EVENT,
      sourceId: source.id,
      source,
      name: CAL_NAME,
      ownerAccount: "Datebook",
      accessLevel: Calendar.CalendarAccessLevel.OWNER,
    });
  }
  const start = new Date(Date.now() - 24 * 60 * 60_000);
  const end = new Date(Date.now() + 14 * 24 * 60 * 60_000);
  const existing = await calendar.listEvents(start, end);
  const byNote = new Map(existing.map((e) => [e.notes ?? "", e]));
  for (const ev of snapshot.calendarEvents ?? []) {
    const notes = ev.notes ?? `datebook:${ev.id}`;
    const found = byNote.get(notes);
    const details = {
      title: ev.title,
      startDate: new Date(ev.startsAt),
      endDate: new Date(ev.endsAt),
      allDay: ev.allDay,
      location: ev.location,
      notes,
    };
    if (found) await found.update(details);
    else await calendar.createEvent(details);
  }
}

TaskManager.defineTask(BG_TASK, async () => {
  return BackgroundFetch.BackgroundFetchResult.NoData;
});

async function registerBackground() {
  try {
    await BackgroundFetch.registerTaskAsync(BG_TASK, {
      minimumInterval: 15 * 60,
      stopOnTerminate: false,
      startOnBoot: true,
    });
  } catch {
    /* already registered or unavailable */
  }
}

export function notificationDeepLink(response: Notifications.NotificationResponse): string | null {
  const data = response.notification.request.content.data as { itemId?: string } | undefined;
  const itemId = typeof data?.itemId === "string" ? data.itemId : undefined;
  const action = response.actionIdentifier;
  if (!itemId) return null;
  if (action === "COMPLETE") return `https://datebookcalendar.vercel.app/today?intent=complete&item=${itemId}`;
  if (action === "SNOOZE") return `https://datebookcalendar.vercel.app/today?intent=snooze&item=${itemId}`;
  return `https://datebookcalendar.vercel.app/today?intent=item&item=${itemId}`;
}

export async function consumeInbox(
  pushBridge: (type: string, payload: unknown) => void
): Promise<string | null> {
  const native = datebookNative();
  const raw = native?.readInbox() ?? null;
  if (!raw) return null;
  native?.clearInbox();
  try {
    const inbox = JSON.parse(raw) as { kind?: string; text?: string; url?: string };
    if (inbox.kind === "text" && inbox.text) {
      pushBridge("nativeIntent", { type: "compose", text: inbox.text });
      return null;
    }
    if (inbox.kind === "url" && inbox.url) {
      pushBridge("nativeIntent", { type: "compose", text: inbox.url });
      return null;
    }
    if (inbox.kind === "ics" && inbox.url) {
      return `https://datebookcalendar.vercel.app/settings?intent=compose&prefill=${encodeURIComponent(inbox.url)}`;
    }
    if (inbox.kind === "pdf") {
      return "https://datebookcalendar.vercel.app/settings";
    }
  } catch {
    /* ignore */
  }
  return null;
}
