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
