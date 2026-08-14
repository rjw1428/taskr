## 1. Configuration

- [x] 1.1 Copy `TRIGGER_TOKEN` from `~/GitProjects/automation/.env` into Taskr's
      `.env` as `PARKING_TRIGGER_TOKEN`. Confirm `.env` is gitignored and already
      listed under `assets:` in `pubspec.yaml`.
- [x] 1.2 Add the parking base URL (`https://api.ryanwilk.com/parking`) as a
      constant in the client, alongside the token read via `flutter_dotenv`.
- [x] 1.3 Update `firebase/firestore.rules` so `todos/{uid}.parkingAlert` is
      readable and writable only by the owning user.

## 2. Backend: scheduling

- [x] 2.1 In `firebase/functions/src/index.ts`, extract the "find today's Work
      Train task and its `startTime`" lookup out of `executeTrainNotification`
      so the parking path can reuse it instead of duplicating the query.
- [x] 2.2 Add a helper that converts a bare `HH:mm` `startTime` plus today's date
      into an absolute epoch timestamp in `America/New_York`. The prompt fires at
      `startTime` exactly, with no lead time.
- [x] 2.3 In the `trainSchedule` fan-out, branch on `parkingAlert === true`
      independently of `trainAlert`, and enqueue a parking prompt Cloud Task on
      the existing `task-reminders` queue.
- [x] 2.4 Give the Cloud Task a deterministic name derived from `{uid}` and the
      date, and catch the `ALREADY_EXISTS` error as a logged no-op so a repeated
      run cannot enqueue a second prompt.
- [x] 2.5 Handle a schedule time already in the past by enqueuing without error
      rather than throwing.

## 3. Backend: delivery

- [x] 3.1 Add a `deliverParkingPrompt` HTTP endpoint alongside `deliverReminder`,
      accepting `{uid, taskId, taskDate}`.
- [x] 3.2 Re-validate at delivery: task still exists, `parkingAlert` still true,
      user still has an `fcmToken`. Each failure returns 200 so Cloud Tasks does
      not retry.
- [x] 3.3 Send the FCM message with `priority: "high"` and
      `channelId: "fcm_default_channel"`, carrying a data payload that identifies
      it as a parking prompt and declares the Yes and No actions.
- [x] 3.4 Reuse `deliverReminder`'s dead-token handling: on
      `messaging/registration-token-not-registered`, clear `fcmToken` and return
      200.
- [x] 3.5 Record the prompt via `recordNotification` with its own type.

## 4. Client: notification display

- [x] 4.0 Before displaying the prompt, call `GET {base}/status` with the bearer
      token. Suppress the notification only on a `200` with a non-empty `active`
      array; on any error, timeout, `409`, or `502`, display it anyway.
- [x] 4.1 In `lib/main.dart`, register an `onDidReceiveNotificationResponse`
      handler and a top-level `@pragma('vm:entry-point')`
      `onDidReceiveBackgroundNotificationResponse` handler on
      `flutterLocalNotificationsPlugin.initialize`.
- [x] 4.2 Display the parking prompt through `flutter_local_notifications` with
      two `AndroidNotificationAction` entries (Yes, No), on the existing
      `fcm_default_channel`. Set the No action to cancel the notification with no
      handler work.
- [x] 4.3 Extend `_firebaseMessagingBackgroundHandler` (currently a debug print)
      to display the prompt when the message arrives with the app backgrounded or
      terminated.
- [ ] 4.4 Verify the prompt appears and both actions are tappable with the app
      fully terminated — this is the case most likely to be broken.

## 5. Client: action dispatch

- [x] 5.1 Replace the hardcoded `actions[0]['action']` lookup in
      `lib/services/messaging.dart` with dispatch on the selected action
      identifier from the notification response.
- [x] 5.2 Route the existing `add-wind-task` action through the new dispatch so
      there is a single code path, and confirm it still creates a wind task.
- [x] 5.3 Wire the No action to dismiss only: no request, no writes.

## 6. Client: triggering payment

- [x] 6.1 Add a parking service call using `dart:io HttpClient` (as
      `calendar.service.dart` and `ai.service.dart` do) issuing
      `GET {base}/park` with `Authorization: Bearer <token>`. The token must not
      appear in the query string.
- [x] 6.2 Handle a missing token by making no request and telling the user the
      feature is unconfigured.
- [x] 6.3 Handle `401` by reporting that the request was not accepted, without
      retrying.
- [x] 6.4 On `200`, confirm only that the request was *sent* — the copy must not
      state or imply that parking has been paid for.
- [x] 6.5 On network error or other non-200, tell the user the request was not
      sent, keeping it distinguishable from an accepted request awaiting its
      result.

## 7. Client: outcome handling

- [x] 7.1 Route incoming pushes with `data['type'] == 'septapark'` to an
      informational path, ensuring they are not treated as actionable prompts.
- [x] 7.2 Surface `paid` and `skipped` with their distinct meanings.
- [x] 7.3 Surface `needs-auth` as "a person must re-authenticate the parking
      account", with no retry affordance.

## 8. Verification

- [x] 8.1 Add tests for the `HH:mm` → `America/New_York` timestamp helper,
      including a start time earlier than the scheduling run.
- [x] 8.2 Add tests for the delivery endpoint's re-validation branches (task
      deleted, opted out, no token, dead token) asserting each returns 200.
- [x] 8.3 Add a client test asserting a `200` response never produces
      payment-confirmed messaging.
- [x] 8.4 Add client tests for the `/status` pre-check covering all four
      branches: active session suppresses, empty `active` displays, network
      failure displays, `409`/`502` displays.
- [ ] 8.5 End-to-end against the service's dry run (`?dry_run=true`) with
      `parkingAlert` set on the developer's own document, before allowing any
      real charge.
- [ ] 8.6 Confirm one real run end to end, watching for the service's `paid`
      push.
