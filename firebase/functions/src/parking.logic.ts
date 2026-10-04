/**
 * Pure logic for the parking prompt.
 *
 * Deliberately imports nothing: keeping it free of firebase-admin is what lets
 * the tests run as plain node without credentials or an emulator.
 */

export const COMMUTE_TIMEZONE = "America/New_York";

export const WORK_TRAIN_TITLE = "Work Train";

/**
 * How far in the past a departure may be and still get a prompt when the task
 * is written. Covers logging the train a few minutes after boarding, without
 * prompting for a task backfilled hours later.
 */
export const PARKING_LATE_GRACE_SECONDS = 30 * 60;

/**
 * Offset, in ms, between UTC and `timeZone` at the given instant.
 */
function timeZoneOffsetMs(utcMs: number, timeZone: string): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const parts: Record<string, string> = {};
  dtf.formatToParts(new Date(utcMs)).forEach((p) => {
    parts[p.type] = p.value;
  });
  const asUtc = Date.UTC(
    Number(parts.year), Number(parts.month) - 1, Number(parts.day),
    Number(parts.hour) % 24, Number(parts.minute), Number(parts.second)
  );
  return asUtc - utcMs;
}

/**
 * Today's date as `YYYY-MM-DD` in `timeZone`.
 *
 * Task date partitions are keyed by the user's local date, so deriving the key
 * from `toISOString()` reads the wrong partition whenever UTC has already rolled
 * over — every evening in New York. That is invisible to a cron that only runs
 * in the morning and immediate to anything invoked on demand.
 */
export function localDateIn(timeZone: string, now: Date = new Date()): string {
  const parts: Record<string, string> = {};
  new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now).forEach((p) => {
    parts[p.type] = p.value;
  });
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/**
 * Converts a `YYYY-MM-DD` date plus a bare `HH:mm` wall-clock time in `timeZone`
 * into epoch seconds. `startTime` on a task carries no zone, and the existing
 * SEPTA logic already compares it against local departure times, so it is
 * interpreted as commute-local.
 *
 * The offset is resolved twice because the correct offset depends on the very
 * instant being computed — a single pass is wrong across a DST boundary.
 */
export function localTimeToEpochSeconds(
  date: string, time: string, timeZone: string
): number {
  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  if ([year, month, day, hour, minute].some((n) => Number.isNaN(n))) {
    throw new Error(`Invalid date/time: ${date} ${time}`);
  }

  const naiveUtc = Date.UTC(year, month - 1, day, hour, minute);
  let epochMs = naiveUtc - timeZoneOffsetMs(naiveUtc, timeZone);
  epochMs = naiveUtc - timeZoneOffsetMs(epochMs, timeZone);
  return Math.floor(epochMs / 1000);
}

/**
 * Whether a scheduled parking prompt should still be sent.
 *
 * Every "no" is a 200 at the endpoint, because none of these is retryable — a
 * Cloud Tasks retry would fail exactly the same way and just burn attempts.
 */
export function parkingPromptDecision(state: {
  taskExists: boolean;
  parkingAlert: unknown;
  fcmToken: string | null | undefined;
  /** startTime the prompt was scheduled for; absent on prompts enqueued before it was recorded. */
  scheduledStartTime?: string;
  /** The task's startTime now. */
  currentStartTime?: unknown;
}): {send: boolean; reason: string} {
  if (!state.taskExists) return {send: false, reason: "Task deleted; skipped"};
  // Editing startTime enqueues a fresh prompt rather than moving this one, so
  // the stale one has to stand down here or the user gets prompted twice.
  if (state.scheduledStartTime !== undefined &&
      state.currentStartTime !== state.scheduledStartTime) {
    return {send: false, reason: "Start time changed; skipped"};
  }
  if (state.parkingAlert !== true) return {send: false, reason: "Opted out; skipped"};
  if (!state.fcmToken) return {send: false, reason: "No FCM token"};
  return {send: true, reason: "Parking prompt sent"};
}

/**
 * Cloud Task name for a parking prompt. The startTime is part of the name so the
 * cron and an on-demand request collide (one prompt) when they agree, and an
 * edited startTime gets a new task instead of ALREADY_EXISTS. Cloud Tasks will
 * not reuse a name for a while after it runs or is deleted, so moving an
 * existing task was never an option.
 */
export function parkingTaskId(uid: string, date: string, startTime: string): string {
  return `parking-${uid}-${date.replace(/-/g, "")}-${startTime.replace(/:/g, "")}`;
}

/**
 * Whether an on-demand request should schedule a parking prompt for a task.
 * The morning cron only sees Work Train tasks that already exist when it runs;
 * the app asks for this when it saves (or retimes) one after that. The app
 * gates the call itself, so this is the authority, not the filter.
 */
export function parkingScheduleDecision(input: {
  task: {title?: unknown; startTime?: unknown} | undefined;
  taskDate: string;
  today: string;
  nowSeconds: number;
}): {schedule: boolean; startTime?: string; reason: string} {
  const {task} = input;
  if (!task || task.title !== WORK_TRAIN_TITLE ||
      typeof task.startTime !== "string" || task.startTime === "") {
    return {schedule: false, reason: "Not a timed Work Train task"};
  }
  const start = task.startTime;
  // Future days are left to that day's cron, so a recurring series being
  // materialised weeks ahead does not enqueue a prompt per occurrence.
  if (input.taskDate !== input.today) return {schedule: false, reason: "Not today"};

  let startSeconds: number;
  try {
    startSeconds = localTimeToEpochSeconds(input.taskDate, start, COMMUTE_TIMEZONE);
  } catch {
    return {schedule: false, reason: "Invalid start time"};
  }
  if (startSeconds < input.nowSeconds - PARKING_LATE_GRACE_SECONDS) {
    return {schedule: false, reason: "Departure already passed"};
  }
  return {schedule: true, startTime: start, reason: "Schedule"};
}
