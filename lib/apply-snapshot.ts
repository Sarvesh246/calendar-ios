import * as Notifications from "expo-notifications";
import * as Calendar from "expo-calendar";
import * as Location from "expo-location";
import * as BackgroundFetch from "expo-background-fetch";
import * as TaskManager from "expo-task-manager";
import * as Linking from "expo-linking";
import { datebookNative } from "../modules/datebook-native";
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

export async function applySnapshot(snapshot: NativeSnapshot) {
  const native = datebookNative();
  await native?.writeSnapshot(JSON.stringify(snapshot));
  await native?.indexSpotlight(JSON.stringify(snapshot.spotlight ?? []));
  await Notifications.setBadgeCountAsync(Math.max(0, snapshot.badge ?? 0));
  await scheduleReminders(snapshot);
  await syncLive(snapshot);
  if (snapshot.appleCalendarSync) await upsertCalendar(snapshot);
  await registerBackground();
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

async function syncLive(snapshot: NativeSnapshot) {
  const native = datebookNative();
  if (!native) return;
  if (snapshot.liveClass) {
    const c = snapshot.liveClass;
    const subtitle =
      c.phase === "live"
        ? c.location
          ? `Until ${new Date(c.endsAt).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })} · ${c.location}`
          : "In session"
        : "Starting soon";
    await native.startLive("class", c.id, c.title, subtitle, c.startsAt, c.endsAt, c.color, c.phase === "live");
  } else {
    await native.endLive("class");
  }
  if (snapshot.liveFocus) {
    const f = snapshot.liveFocus;
    const end = f.targetEndsAt ?? f.startedAt + f.itemElapsedMs + 60_000;
    const start = f.targetEndsAt ? f.targetEndsAt - (f.targetEndsAt - Date.now() + (f.running ? 0 : 0)) : f.startedAt;
    const subtitle = f.running ? "On the clock" : "Paused";
    await native.startLive(
      "focus",
      f.itemId,
      f.title,
      subtitle,
      f.targetEndsAt ? Date.now() : start,
      f.targetEndsAt ?? end,
      "#0A84FF",
      f.running
    );
  } else {
    await native.endLive("focus");
  }
}

async function upsertCalendar(snapshot: NativeSnapshot) {
  const perm = await Calendar.requestCalendarPermissionsAsync();
  if (perm.status !== "granted") return;
  const calendars = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
  let cal = calendars.find((c) => c.title === CAL_NAME && c.allowsModifications);
  let calendarId = cal?.id;
  if (!cal) {
    const source =
      calendars.find((c) => c.source?.name === "Default")?.source ??
      calendars.find((c) => c.allowsModifications)?.source;
    if (!source) return;
    calendarId = await Calendar.createCalendarAsync({
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
  if (!calendarId) return;
  const start = new Date(Date.now() - 24 * 60 * 60_000);
  const end = new Date(Date.now() + 14 * 24 * 60 * 60_000);
  const existing = await Calendar.getEventsAsync([calendarId], start, end);
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
      calendarId,
    };
    if (found) await Calendar.updateEventAsync(found.id, details);
    else await Calendar.createEventAsync(calendarId, details);
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
