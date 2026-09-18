export type NativeSnapshot = {
  clock24h: boolean;
  badge: number;
  reminders: {
    id: string;
    itemId: string;
    title: string;
    body: string;
    fireAt: number | null;
    kind: "time" | "class" | "location";
    place?: { name: string; lat: number; lng: number; radiusMeters: number };
  }[];
  today: unknown[];
  upNext: unknown[];
  assignments: unknown[];
  classes: unknown[];
  liveClass: {
    id: string;
    title: string;
    startsAt: number;
    endsAt: number;
    location?: string;
    color: string;
    phase: "soon" | "live";
  } | null;
  liveFocus: {
    itemId: string;
    title: string;
    running: boolean;
    itemElapsedMs: number;
    sessionElapsedMs: number;
    targetEndsAt: number | null;
    startedAt: number;
    color?: string;
  } | null;
  spotlight: unknown[];
  calendarEvents: {
    id: string;
    title: string;
    startsAt: number;
    endsAt: number;
    allDay: boolean;
    location?: string;
    notes?: string;
  }[];
  appleCalendarSync: boolean;
  feeds: { id: string; url: string; name: string }[];
};
