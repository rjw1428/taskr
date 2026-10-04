/**
 * Pure-logic tests for the parking prompt. Run with:
 *   npm run build && node --test lib/parking.test.js
 *
 * Only pure functions are covered here — anything touching Firestore or FCM is
 * verified against the emulator instead.
 */
import {test} from "node:test";
import * as assert from "node:assert";

import {
  localDateIn,
  localTimeToEpochSeconds,
  parkingPromptDecision,
  parkingTaskId,
  parkingScheduleDecision,
} from "./parking.logic";

const TZ = "America/New_York";

test("uses the local date when UTC has already rolled over", () => {
  // 2026-08-14T00:38Z is 8:38pm on the 13th in New York. Deriving the partition
  // key from toISOString() here reads tomorrow's tasks and finds nothing — the
  // failure seen when the schedule was triggered on demand in the evening.
  const evening = new Date("2026-08-14T00:38:00Z");
  assert.strictEqual(localDateIn(TZ, evening), "2026-08-13");
  assert.notStrictEqual(localDateIn(TZ, evening), evening.toISOString().split("T")[0]);
});

test("agrees with UTC during the morning cron window", () => {
  // 11:00Z is 07:00 in New York, where both dates match — which is why the bug
  // stayed invisible on the scheduled path.
  const morning = new Date("2026-08-13T11:00:00Z");
  assert.strictEqual(localDateIn(TZ, morning), "2026-08-13");
  assert.strictEqual(localDateIn(TZ, morning), morning.toISOString().split("T")[0]);
});

test("uses the local date across a year boundary", () => {
  const newYear = new Date("2027-01-01T02:15:00Z");
  assert.strictEqual(localDateIn(TZ, newYear), "2026-12-31");
});

test("converts a morning commute time during EDT", () => {
  // 2026-08-13 08:15 EDT is UTC-4, so 12:15 UTC.
  const seconds = localTimeToEpochSeconds("2026-08-13", "08:15", TZ);
  assert.strictEqual(new Date(seconds * 1000).toISOString(), "2026-08-13T12:15:00.000Z");
});

test("converts a morning commute time during EST", () => {
  // 2026-01-13 08:15 EST is UTC-5, so 13:15 UTC. Same wall clock, different
  // offset — this is the case a fixed offset would get wrong.
  const seconds = localTimeToEpochSeconds("2026-01-13", "08:15", TZ);
  assert.strictEqual(new Date(seconds * 1000).toISOString(), "2026-01-13T13:15:00.000Z");
});

test("converts correctly on the spring-forward day", () => {
  // DST begins 2026-03-08 at 02:00. A 08:15 departure that day is already EDT.
  const seconds = localTimeToEpochSeconds("2026-03-08", "08:15", TZ);
  assert.strictEqual(new Date(seconds * 1000).toISOString(), "2026-03-08T12:15:00.000Z");
});

test("a start time earlier than the scheduling run still resolves", () => {
  // The cron runs at 11:00 UTC (07:00 ET). A 06:30 departure is in the past by
  // then; it must produce a valid past timestamp rather than throwing, so Cloud
  // Tasks can dispatch it promptly.
  const seconds = localTimeToEpochSeconds("2026-08-13", "06:30", TZ);
  assert.strictEqual(new Date(seconds * 1000).toISOString(), "2026-08-13T10:30:00.000Z");
  assert.ok(seconds < localTimeToEpochSeconds("2026-08-13", "11:00", TZ));
});

test("rejects a malformed start time", () => {
  assert.throws(() => localTimeToEpochSeconds("2026-08-13", "not-a-time", TZ));
});

test("sends when the task exists, the user opted in, and a token is present", () => {
  const decision = parkingPromptDecision({
    taskExists: true, parkingAlert: true, fcmToken: "tok",
  });
  assert.strictEqual(decision.send, true);
});

test("skips when the task was deleted after scheduling", () => {
  const decision = parkingPromptDecision({
    taskExists: false, parkingAlert: true, fcmToken: "tok",
  });
  assert.strictEqual(decision.send, false);
  assert.match(decision.reason, /deleted/i);
});

test("skips when the user opted out after scheduling", () => {
  const decision = parkingPromptDecision({
    taskExists: true, parkingAlert: false, fcmToken: "tok",
  });
  assert.strictEqual(decision.send, false);
  assert.match(decision.reason, /opted out/i);
});

test("skips when the opt-in flag is absent rather than false", () => {
  const decision = parkingPromptDecision({
    taskExists: true, parkingAlert: undefined, fcmToken: "tok",
  });
  assert.strictEqual(decision.send, false);
});

test("skips when the user has no FCM token", () => {
  const decision = parkingPromptDecision({
    taskExists: true, parkingAlert: true, fcmToken: null,
  });
  assert.strictEqual(decision.send, false);
  assert.match(decision.reason, /token/i);
});

test("skips a prompt whose task has since been retimed", () => {
  const decision = parkingPromptDecision({
    taskExists: true, parkingAlert: true, fcmToken: "tok",
    scheduledStartTime: "07:10", currentStartTime: "09:40",
  });
  assert.strictEqual(decision.send, false);
  assert.match(decision.reason, /start time changed/i);
});

test("sends when the scheduled start time still matches", () => {
  const decision = parkingPromptDecision({
    taskExists: true, parkingAlert: true, fcmToken: "tok",
    scheduledStartTime: "09:40", currentStartTime: "09:40",
  });
  assert.strictEqual(decision.send, true);
});

test("sends a prompt enqueued before the start time was recorded", () => {
  // Cloud Tasks already in the queue at deploy time carry no startTime.
  const decision = parkingPromptDecision({
    taskExists: true, parkingAlert: true, fcmToken: "tok",
    currentStartTime: "09:40",
  });
  assert.strictEqual(decision.send, true);
});

test("task name is stable for the same departure and differs when retimed", () => {
  assert.strictEqual(
    parkingTaskId("u1", "2026-10-02", "09:40"),
    "parking-u1-20261002-0940"
  );
  assert.notStrictEqual(
    parkingTaskId("u1", "2026-10-02", "09:40"),
    parkingTaskId("u1", "2026-10-02", "07:10")
  );
});

// 2026-10-02 08:00 EDT — after the 07:00 cron, which is the case that was missed.
const AFTER_CRON = Math.floor(Date.parse("2026-10-02T12:00:00Z") / 1000);
const TODAY = "2026-10-02";
const train = (startTime?: string) => ({title: "Work Train", startTime});

const decide = (task: any, taskDate = TODAY) => parkingScheduleDecision({
  task, taskDate, today: TODAY, nowSeconds: AFTER_CRON,
});

test("schedules a Work Train added after the morning cron", () => {
  assert.deepStrictEqual(
    decide(train("09:40")),
    {schedule: true, startTime: "09:40", reason: "Schedule"}
  );
});

test("schedules a retimed Work Train at its new time", () => {
  // The old prompt stands down at delivery; see parkingPromptDecision.
  assert.strictEqual(decide(train("10:15")).startTime, "10:15");
});

test("skips a task that no longer exists", () => {
  assert.strictEqual(decide(undefined).schedule, false);
});

test("skips other tasks and untimed Work Trains", () => {
  for (const task of [{title: "Gym", startTime: "09:40"}, train(undefined), train("")]) {
    assert.strictEqual(decide(task).schedule, false);
  }
});

test("matches the title exactly, as the cron does", () => {
  assert.strictEqual(decide({title: "work train", startTime: "09:40"}).schedule, false);
});

test("leaves other days to that day's cron", () => {
  const d = decide(train("09:40"), "2026-10-03");
  assert.strictEqual(d.schedule, false);
  assert.match(d.reason, /today/i);
});

test("still prompts for a train logged shortly after boarding", () => {
  assert.strictEqual(decide(train("07:45")).schedule, true);
});

test("does not prompt for a departure well in the past", () => {
  const d = decide(train("07:15"));
  assert.strictEqual(d.schedule, false);
  assert.match(d.reason, /passed/i);
});

test("does not throw on a malformed start time", () => {
  assert.strictEqual(decide(train("soon")).schedule, false);
});
