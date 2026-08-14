## Context

Taskr already sends a train-status push on Work Train days.
`trainSchedule` (`firebase/functions/src/index.ts:16`) is an
`onSchedule("every day 11:00")` cron that fans out to
`executeTrainNotification()` for every user whose `todos/{uid}` document has
`trainAlert === true`. That function looks up today's `Work Train` task, reads
`todo.startTime`, queries SEPTA for the next train after it, and sends an
informational FCM message.

Separately, the app has a Cloud Tasks–backed reminder mechanism:
`scheduleReminder` (`:1004`) enqueues an HTTP Cloud Task with an exact
`scheduleTime`, and `deliverReminder` (`:1071`) is the endpoint it calls, which
sends a high-priority FCM message on the `fcm_default_channel` Android channel.
This is the project's existing answer to "deliver something at a specific
wall-clock time", and it already handles the two failure modes that matter:
a task deleted between scheduling and delivery, and a dead FCM registration
token.

On the client, `lib/main.dart:92` initializes `flutter_local_notifications` and
creates the high-importance `fcm_default_channel`, but registers no
`onDidReceiveNotificationResponse` handler and no background response handler.
`FirebaseMessageService.handleMessage` (`lib/services/messaging.dart:28`)
understands an `actions` convention in the FCM data payload, but only ever reads
`actions[0]['action']` — it cannot distinguish which action a user chose,
because nothing in this repo currently sends more than one.

The parking service (`~/GitProjects/automation`) is already built and deployed
at `https://api.ryanwilk.com/parking`. It is documented in that project's
`INTEGRATION.md`. Taskr does not need to build any part of it — only to call it.

## Goals / Non-Goals

**Goals:**

- Deliver an actionable "pay for parking?" notification at the Work Train task's
  `startTime`, not on a fixed daily cron.
- Make "Yes" a single tap that results in parking being paid for, with the app
  closed.
- Make "No" cost nothing — a pure dismissal, no network call, no state written.
- Keep the parking trigger token out of source control.
- Never charge twice because of anything Taskr does.

**Non-Goals:**

- Building or changing the parking service itself. Its API is fixed.
- Displaying the payment *outcome*. The service already pushes its own result to
  Taskr as `data.type == "septapark"`, deliberately without an `actions` key so
  it renders through the ordinary system-notification path.
- Automating re-authentication. `needs-auth` requires a human to read an SMS
  code; the client surfaces it and stops.
- A settings UI for `parkingAlert`. Like the existing `trainAlert`, it is set
  directly in Firestore. Adding UI for both is worth doing, but separately.
- iOS notification actions. The existing notification path is Android-only
  (`fcm_default_channel`, `AndroidInitializationSettings`), and this change
  follows it rather than widening scope.

## Decisions

### Schedule the prompt from the existing train cron, via Cloud Tasks

`trainSchedule` already runs daily, already resolves today's `Work Train` task,
and already parses `todo.startTime`. It gains a second responsibility: when
`parkingAlert === true`, compute the absolute timestamp for `startTime` in
`America/New_York` on today's date and enqueue a Cloud Task on the existing
`task-reminders` queue targeting a new `deliverParkingPrompt` endpoint.

*Alternatives considered.* A second fixed cron (`onSchedule("every day HH:MM")`)
was rejected because the whole point is that the prompt lands at departure, and
`startTime` varies per day. A high-frequency poller (every 5 minutes, checking
whether any user's `startTime` just passed) was rejected as strictly worse than
Cloud Tasks: more invocations, coarser timing, and it would duplicate a
mechanism the project already has.

*Consequence.* The prompt cannot fire for a Work Train task whose `startTime` is
earlier in the day than the cron itself. This is accepted — the cron runs at
11:00 UTC (07:00 ET) and the train task is a morning commute, but the delivery
endpoint must tolerate a schedule time already in the past rather than erroring.

### Enqueue idempotently, keyed by user and date

Cloud Tasks assigns a name when one is not supplied. This change supplies one
derived from `{uid}-{date}-parking`, so a re-run of `trainSchedule` on the same
day (a retry, a manual invocation of the existing HTTP trigger) collides with
the already-created task and is rejected with `ALREADY_EXISTS` rather than
enqueuing a second prompt. That error is caught and logged as a no-op.

*Why it matters.* Two prompts is not merely untidy; it is two chances to tap
Yes. The parking service's `skipped` guard means the second tap would not
double-charge, but relying on the far end for correctness we can guarantee here
is the wrong default.

### The "Yes" action calls the service directly from the device

The client holds `PARKING_TRIGGER_TOKEN` and issues
`GET https://api.ryanwilk.com/parking/park` with an
`Authorization: Bearer <token>` header itself.

*Alternative considered and rejected by the user.* Proxying through a callable
Cloud Function would keep the token server-side as a `defineSecret` value and
make rotation a config change rather than a release. The direct call was chosen
for simplicity; the trade-off is recorded under Risks.

*Token storage.* `.env`, read via `flutter_dotenv`, alongside the existing
`GEMINI_API_KEY` and `ALGOLIA_SEARCH_KEY`. `.env` is a bundled asset and is not
committed. Note this means the token is extractable from a distributed APK — see
Risks.

*HTTP client.* `dart:io HttpClient`, as `calendar.service.dart`,
`ai.service.dart`, and `goal.service.dart` already use. No new dependency.

### Treat HTTP 200 as "accepted", never as "paid"

The service is fire-and-forget: it validates, starts the purchase in the
background, and returns `{"success": true, "requestId": "…"}` immediately. The
client must not tell the user parking is paid for on the strength of a 200. It
acknowledges that the request went through, and the real outcome arrives
separately as the service's own `septapark` push.

This is the single most important behavioural constraint in the change, and the
one most likely to be got wrong by someone reading only the status code.

### Suppress the prompt when parking is already active, checked client-side

A prompt is pointless if the lot is already paid for. Before displaying the
notification, the client calls `GET /status` and, if the response lists an active
session, drops the prompt without showing anything.

*Why client-side.* The check needs the bearer token. Doing it in
`deliverParkingPrompt` would require adding `TRIGGER_TOKEN` as a
`defineSecret` on the backend as well — a second copy of the credential in a
second place, for a check that is not security-relevant. The client already
holds the token for the `/park` call, so the check costs nothing new there.

*Fail open.* If `/status` errors, times out, or returns `409`/`502`, the client
displays the prompt anyway. The alternative — swallowing the prompt on a
transient network failure — risks silently not paying for parking, which is far
worse than one unnecessary notification. The service's own `skipped` behaviour
means a redundant Yes buys nothing.

### Render actions with flutter_local_notifications, not FCM

FCM cannot render notification action buttons. The prompt is therefore sent as a
data-carrying message and displayed by the client through
`flutter_local_notifications` using an Android notification with two
`AndroidNotificationAction` entries. This requires:

- A `@pragma('vm:entry-point')` top-level background response handler passed as
  `onDidReceiveBackgroundNotificationResponse`, because the tap must work when
  the app is not running. A closure or instance method will not survive the
  isolate boundary.
- The `No` action declared with `cancelNotification: true` and no payload
  handling, so dismissal needs no code path at all.
- The existing `_firebaseMessagingBackgroundHandler` in `lib/main.dart:44`,
  currently a debug print, to actually display the notification for this message
  type when the app is backgrounded.

### The prompt push is data-only

The prompt carries no `notification` block; its title and body ride inside
`data`. Android's FCM SDK auto-displays any message that has a `notification`
block whenever the app is not in the foreground, and that system-drawn copy has
no action buttons and merely opens the app on tap. It also arrives *alongside*
the one the client draws — so a single push produced two notifications, the
useless one first.

This is the one arrangement that cannot be worked around client-side: the
auto-display happens before any Dart code runs. Data-only is what makes the
client the sole author of the notification.

*Consequence.* Nothing is displayed unless the client draws it, so the
background handler must initialize `WidgetsFlutterBinding` before touching the
plugin or reading the `.env` asset — a cold isolate has no platform channels.
A force-stopped app also receives no data messages at all, which is accepted.

### Declare ActionBroadcastReceiver in the app manifest

`flutter_local_notifications` 18.0.1 ships a manifest containing only
permissions — no receivers. An app using notification actions has to declare
`com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver` itself.
Without it the buttons still render and still carry pending intents, but those
intents target a component that does not exist, so a tap does nothing at all.
Taskr had never needed this, because nothing used action buttons before.

### The notification is not the only way to answer

Action buttons are the fast path, but they vanish the moment the notification is
dismissed or its body is tapped — and a body tap merely opens the app, which
strands the user with the question and no way to answer it. So the same yes/no
is reachable in-app: on a body tap (live or via launch details after a cold
start) and from the notification centre entry, which outlives the shade.

Answering in-app reports its outcome as a snackbar rather than another
notification, since the app is by definition in front of the user there. The
"accepted, not paid" wording is the same in both paths.

### Register exactly one background message handler

`FirebaseMessaging.onBackgroundMessage` must be given a top-level function
annotated `@pragma('vm:entry-point')`; a closure cannot be resolved across the
isolate boundary. Registering a second handler silently replaces the first, so
there is exactly one registration, in `main.dart`.

### Generalize the client's action dispatch

`handleMessage`'s `actions[0]['action']` is replaced by dispatch on the action
identifier the user actually selected (`NotificationResponse.actionId`). The
existing `add-wind-task` behaviour is preserved through the new dispatch rather
than being left on the old path, so there is one way this works, not two.

### Surface `needs-auth` distinctly

Of the service's result statuses, `needs-auth` is the only one where retrying is
guaranteed useless — the upstream SEPTA session expired and restoring it needs a
human to read an SMS code. The client routes that status to a message that says
so, instead of letting it read like a transient failure the user might tap
through again.

## Risks / Trade-offs

**The token ships inside the app binary.** → Accepted deliberately. `.env` keeps
it out of git, and the service's least-privilege design means a leaked token can
at worst buy the usual session at the configured lot — it cannot redirect the
purchase, change the plate, or inflate the amount, because those are server-side
config. Rotation requires a release; if that becomes painful, the proxy-function
alternative above is the migration path.

**A 200 misread as a receipt.** → The client never claims payment succeeded on a
200. Spec-level scenarios pin this, and the confirmation copy says the request
was sent, not that parking is paid.

**Double-tap or duplicate prompt.** → Three layers: named Cloud Tasks prevent a
duplicate prompt; the notification is cancelled on tap so it cannot be tapped
twice; and the service itself reports `skipped` without creating an order when a
session is already active for the plate.

**The tap fires with no network.** → The `HttpClient` call fails and the user is
told the trigger did not go through, explicitly distinguishing "we never asked"
from "we asked and don't know yet". Silently swallowing this is the bad outcome:
the user would believe parking was being handled when nothing was sent.

**The `/status` pre-check swallows a prompt it shouldn't.** → It fails open: any
error, timeout, or non-`200` displays the prompt. Only an unambiguous `200` with
a non-empty `active` array suppresses it. A missed notification is a day of
unpaid parking; a redundant one costs a tap.

**Android kills the background isolate before the request completes.** → The
call is short, but the handler awaits it rather than firing and returning, and
failures surface as a local notification the user can act on.

**Timezone drift on `startTime`.** → `todo.startTime` is a bare `HH:mm` string
with no zone. It is interpreted as `America/New_York`, consistent with the
existing SEPTA logic in `executeTrainNotification`, which compares it directly
against SEPTA's local departure times.

**Timezone drift on the task *date*.** → Task partitions are keyed by local date,
but the existing code derived the key from `new Date().toISOString()`, which is
UTC. Every evening in New York, UTC has already rolled over and the lookup reads
tomorrow's empty partition. This was invisible on the scheduled path — the cron
runs in the morning, when both dates agree — and appeared immediately the first
time the fan-out was triggered on demand in the evening. Both commute functions
now derive the key with `localDateIn(COMMUTE_TIMEZONE)`.

Note `getIncompleteGoalTasksForToday` still uses the UTC form. It has the same
latent bug but is only ever reached from crons that run when the dates agree, so
it was left alone rather than changed as a side effect of this work.

**The prompt fires on a day the user is not commuting.** → The task's existence
is the signal, same as the existing train alert. Tapping nothing is a safe
default and costs nothing.

## Migration Plan

1. Add `PARKING_TRIGGER_TOKEN` to `.env` locally, copied from the automation
   project's `.env`. No commit.
2. Deploy the backend changes. With no user having `parkingAlert === true`, the
   new code path is inert.
3. Set `parkingAlert: true` on the developer's own `todos/{uid}` document and
   verify a Cloud Task is enqueued at the right timestamp.
4. Verify end to end against the service's dry-run path
   (`?dry_run=true`) before allowing a real charge.

*Rollback.* Set `parkingAlert` back to `false`; the feature goes dormant without
a deploy. Any already-enqueued Cloud Task can be left to fire — its delivery
endpoint re-checks the flag.

## Open Questions

None outstanding. Two were resolved during design:

- **Lead time before `startTime`** — none. The prompt fires at `startTime`
  exactly.
- **Suppressing the prompt when a session is already active** — yes, via a
  client-side `/status` check that fails open. See Decisions.
