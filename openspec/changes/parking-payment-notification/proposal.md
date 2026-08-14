## Why

On days with a "Work Train" task, parking at the SEPTA lot has to be paid for
manually before the train. A service already exists to do it
(`~/GitProjects/automation`, exposed at `https://api.ryanwilk.com/parking`), but
nothing triggers it — the user still has to remember, open something, and fire
the request. Taskr already knows when the train task starts and already sends a
train-status push ahead of it, so it is the natural place to put a one-tap
"pay for parking?" prompt at the moment it is actually relevant.

## What Changes

- **New `parkingAlert` user flag** on `todos/{uid}`, alongside the existing
  `trainAlert`. Only users with it enabled get the prompt.
- **A parking prompt scheduled at the Work Train `startTime`.** The existing
  daily `trainSchedule` cron (which already reads today's `Work Train` task and
  its `startTime`) enqueues a Cloud Task for that exact timestamp, reusing the
  `scheduleReminder`/`deliverReminder` Cloud Tasks pattern rather than adding a
  new scheduling mechanism. This is distinct from the existing train-status
  push, which stays on its current fixed pre-departure cron.
- **An actionable FCM notification** with Yes / No buttons. FCM alone cannot
  render action buttons, so the client displays it through
  `flutter_local_notifications` (already a dependency) using an Android
  notification category with two actions.
  - **No** dismisses the notification and does nothing else.
  - **Yes** calls `GET https://api.ryanwilk.com/parking/park` with
    `Authorization: Bearer <TRIGGER_TOKEN>` directly from the app.
- **Token distribution.** `TRIGGER_TOKEN` is copied from the automation
  project's `.env` into Taskr's `.env` as `PARKING_TRIGGER_TOKEN` and read
  through `flutter_dotenv`, matching how `GEMINI_API_KEY` and
  `ALGOLIA_SEARCH_KEY` are already handled. See Impact for the accepted risk.
- **Result handling.** The automation service already pushes its own outcome to
  Taskr as `data.type == "septapark"` with no `actions` key, so it falls through
  to the ordinary system-notification path and needs no new delivery work. The
  client adds a small amount of routing so `needs-auth` is surfaced as
  "re-authenticate" rather than looking like a transient failure — retrying it
  never succeeds.
- **Generalized action handling on the client.** `FirebaseMessageService.handleMessage`
  currently hardcodes `actions[0]['action']` and only understands
  `add-wind-task`; it is extended to dispatch on the action the user actually
  tapped.

## Capabilities

### New Capabilities

- `parking-payment-prompt`: scheduling, delivery, and handling of the
  at-departure "pay for parking?" actionable notification, including the
  `parkingAlert` opt-in, the Yes/No actions, the authenticated call to the
  parking service, and how the service's asynchronous result is surfaced.

### Modified Capabilities

None. `notification-center` gains a new recorded notification type but its
existing requirements are unchanged.

## Impact

**Backend** — `firebase/functions/src/index.ts`
- `trainSchedule` / `executeTrainNotification`: also enqueue the parking prompt
  Cloud Task at `todo.startTime` when `parkingAlert === true`.
- A new delivery endpoint alongside `deliverReminder`, sending the prompt with
  an `actions` payload. It reuses `deliverReminder`'s dead-token handling
  (clearing `fcmToken` on `messaging/registration-token-not-registered`) and its
  "task was deleted, skip silently" guard.
- Reuses the existing `task-reminders` Cloud Tasks queue.

**Client** — `lib/services/messaging.dart`, notification setup in `lib/main.dart`
- An Android notification category/channel with Yes and No actions, plus a
  background action handler (the tap must work with the app closed).
- An HTTP call to the parking service, using `dart:io HttpClient` as
  `calendar.service.dart`, `ai.service.dart`, and `goal.service.dart` already
  do. No new dependency.

**Config** — `.env` gains `PARKING_TRIGGER_TOKEN`, copied from the automation
project. It is already a bundled asset (`pubspec.yaml`) and is not committed.

**Firestore** — `todos/{uid}` gains `parkingAlert` (bool); rules must keep it
readable only by the owning user.

**External** — `https://api.ryanwilk.com/parking/park`. The endpoint is
fire-and-forget: `200` means accepted, not paid. It is idempotent in practice
(an already-active session reports `skipped`), serialized, price-capped, and
card-pinned, so a double-tap cannot double-charge and a leaked token can at
worst buy the usual ~$2.00 session.

**Accepted risk** — calling the service directly from the app ships the bearer
token inside the binary, and rotating it requires a new release. This was chosen
deliberately over proxying through a Cloud Function that would hold the token as
a `defineSecret` value. The `.env` asset keeps it out of source control, and the
service's least-privilege design bounds the blast radius: a leaked token can at
worst buy the usual session at the configured lot.
