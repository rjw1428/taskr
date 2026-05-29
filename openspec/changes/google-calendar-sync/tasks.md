## 1. Google Cloud Console setup

- [x] 1.1 In the existing OAuth consent screen, add the scope `https://www.googleapis.com/auth/calendar`.
- [x] 1.2 Create a new **Web** OAuth 2.0 Client. Capture its client ID and client secret.
- [x] 1.3 Add `https://taskr-1428.firebaseapp.com/__/auth/handler` (or equivalent) as an authorized redirect URI on the web client. Confirm the existing Android client is unchanged.
- [x] 1.4 Add `GOOGLE_OAUTH_CLIENT_SECRET` and `GOOGLE_OAUTH_WEB_CLIENT_ID` as Cloud Function secrets via `firebase functions:secrets:set`.

## 2. Firestore schema + rules

- [x] 2.1 Add a new top-level collection plan: `secrets/{uid}` holding sensitive per-user fields (refresh token).
- [x] 2.2 Update `firestore.rules` with a `match /secrets/{uid}` block: `allow read, write: if false;` (Admin SDK only).
- [x] 2.3 Document the new fields in this change: `todos/{uid}.calendarConnectedAt`, `todos/{uid}.calendarSyncToken`, `secrets/{uid}.calendarRefreshToken`, `tasks/{date}/items/{taskId}.calendarEventId`.
- [x] 2.4 Deploy the updated rules.

## 3. Auth scope extension (Flutter)

- [x] 3.1 In `lib/services/auth.service.dart`, update the `GoogleSignIn` instance to declare the `calendar` scope is *available* (not required at sign-in).
- [x] 3.2 Configure `GoogleSignIn` with `serverClientId = <web client ID>` so consent can return a `serverAuthCode`.
- [x] 3.3 Add a method `requestCalendarScope()` that calls `googleUser.authentication` after `googleUser?.requestScopes([CalendarApi.calendarScope])` and returns the access token + serverAuthCode.

## 4. Calendar service (Flutter)

- [x] 4.1 Create `lib/services/calendar.service.dart` with a singleton `CalendarService`.
- [x] 4.2 Implement `Future<bool> isConnected(String uid)` — reads `todos/{uid}.calendarConnectedAt`.
- [x] 4.3 Implement `Future<void> connect()` — runs `requestCalendarScope`, ships `serverAuthCode` to `exchangeCalendarAuthCode` Cloud Function via `cloud_functions`, surfaces errors.
- [x] 4.4 Implement `Future<void> disconnect()` — calls `disconnectCalendar` cloud function.
- [x] 4.5 Implement `Future<String> sendTaskToCalendar(Task task, {String? rrule})` — uses access token to POST `https://www.googleapis.com/calendar/v3/calendars/primary/events`; sets `summary`, `description`, all-day `start.date`/`end.date`, optional `recurrence`, and `extendedProperties.private.taskrId`. Returns the new `eventId`.
- [x] 4.6 Implement `Future<String?> _rruleForRecurringTask(Task task)` — maps the recurring template to an RFC 5545 RRULE; returns `null` for non-recurring tasks.
- [x] 4.7 Implement `Future<void> updateTaskEvent(Task task)` — PATCH the existing `calendarEventId` if set; otherwise call `sendTaskToCalendar`.

## 5. Settings page (Flutter)

- [x] 5.1 Create `lib/settings/settings_page.dart` with a `ListView` whose first item is the Google Calendar row.
- [x] 5.2 Row uses a `FutureBuilder` (or stream of the user doc) to show "Not connected" + Connect button or "Connected since <date>" + Disconnect button.
- [x] 5.3 Connect button calls `CalendarService().connect()` and shows a snackbar on success/error.
- [x] 5.4 Disconnect button shows a confirmation dialog before calling `CalendarService().disconnect()`.
- [x] 5.5 Add a settings gear icon to the app bar (placement: top-right of home shell) that routes to the settings page.

## 6. Send to Calendar action (Flutter)

- [x] 6.1 In `lib/task_list/task_item.dart`, add a "Send to Calendar" item to the popup menu, gated on `isConnected && task.dueDate != null`.
- [x] 6.2 Wire the action to `CalendarService().sendTaskToCalendar(task)` (or `updateTaskEvent` if `calendarEventId` is already set).
- [x] 6.3 On success, persist `calendarEventId` on the task via `TaskService.updateTask`.
- [x] 6.4 On failure: snackbar with the error; do not write `calendarEventId`.

## 7. exchangeCalendarAuthCode cloud function

- [x] 7.1 Add a new `onCall` function in `firebase/functions/src/index.ts`.
- [x] 7.2 Verify the caller is authenticated; reject otherwise.
- [x] 7.3 POST to `https://oauth2.googleapis.com/token` with `code`, `client_id`, `client_secret`, `grant_type=authorization_code`, `redirect_uri=postmessage` (or the registered URI per `google_sign_in` docs).
- [x] 7.4 Extract `refresh_token` from the response; write to `secrets/{uid}.calendarRefreshToken`.
- [x] 7.5 Write `todos/{uid}.calendarConnectedAt = FieldValue.serverTimestamp()`.
- [x] 7.6 Return `{ ok: true }` on success; throw `HttpsError` on failure.

## 8. disconnectCalendar cloud function

- [x] 8.1 Add a new `onCall` function in `firebase/functions/src/index.ts`.
- [x] 8.2 Read the refresh token from `secrets/{uid}`.
- [x] 8.3 POST to `https://oauth2.googleapis.com/revoke?token=<refreshToken>` (best-effort; log but don't fail on error).
- [x] 8.4 Delete `secrets/{uid}.calendarRefreshToken`, `todos/{uid}.calendarSyncToken`, `todos/{uid}.calendarConnectedAt`.
- [x] 8.5 Return `{ ok: true }`.

## 9. importCalendarEvents cloud function

- [x] 9.1 Add `import` from `googleapis` (`npm install googleapis` in `firebase/functions`).
- [x] 9.2 Add an `onSchedule("every 60 minutes")` function with `secrets: [GOOGLE_OAUTH_CLIENT_SECRET, GOOGLE_OAUTH_WEB_CLIENT_ID]`.
- [x] 9.3 Iterate `todos` collection; filter to docs with non-null `calendarConnectedAt`.
- [x] 9.4 For each user: read refresh token from `secrets/{uid}`; build an OAuth2 client; mint an access token (in-memory only).
- [x] 9.5 Call `events.list({ calendarId: 'primary', syncToken, singleEvents: true, privateExtendedProperty: '!taskrId' })`. If no syncToken: use `timeMin=now`, `timeMax=now+30d`. (Note: Google does not support `!=` filter on extended props; instead, fetch all and filter `taskrId` in code.)
- [x] 9.6 For each returned event: skip if `extendedProperties.private.taskrId` is set; otherwise upsert a task at `tasks/{eventStartDate}/items/` keyed by lookup on `calendarEventId`.
- [x] 9.7 If `event.status === 'cancelled'`: delete any task with the matching `calendarEventId`.
- [x] 9.8 On 410 Gone: clear `calendarSyncToken` and break out of the user (next run will reseed).
- [x] 9.9 On `invalid_grant`: clear `secrets/{uid}.calendarRefreshToken` and `todos/{uid}.calendarConnectedAt` so the user is prompted to reconnect.
- [x] 9.10 Write `nextSyncToken` to `todos/{uid}.calendarSyncToken` inside a transaction (to avoid stale-write races between overlapping runs).
- [x] 9.11 Log per-user counts: `{ uid, imported, updated, cancelled, errors }`.

## 10. Helper: event-to-task mapping (cloud function)

- [x] 10.1 Write `eventToTaskFields(event)` returning `{ title, description, dueDate, priority: 'low', completed: false, added, calendarEventId, tags: [] }`.
- [x] 10.2 Resolve `dueDate`: prefer `event.start.date`; else parse `event.start.dateTime` and take its date portion in the event's timezone.
- [x] 10.3 Write `findTaskByEventId(uid, eventId)` — scoped query across recent date documents (last 60 days, next 60 days) returning the matching task ref or null. (Simpler v1 alternative: store `tasks/{uid}/byEventId/{eventId}` index doc.)

## 11. Deploy

- [x] 11.1 Update `firebase/functions/package.json` to add `googleapis`.
- [x] 11.2 Run `npm run deploy` from `firebase/functions` for the 3 new functions (`exchangeCalendarAuthCode`, `disconnectCalendar`, `importCalendarEvents`). Deploy only the new functions to preserve existing remote ones.
- [ ] 11.3 Confirm the schedule for `importCalendarEvents` is registered in Cloud Scheduler.

## 12. Manual verification

- [ ] 12.1 Open Settings; row reads "Not connected".
- [ ] 12.2 Tap Connect; grant calendar consent; row updates to "Connected since <today>".
- [ ] 12.3 Open a one-shot task with a due date; "Send to Calendar" appears in the popup; tap it; confirm an all-day event appears on the primary calendar.
- [ ] 12.4 Open the event in Google Calendar UI and confirm it has an `extendedProperties.private.taskrId` (visible via Calendar API explorer).
- [ ] 12.5 Send a recurring task; confirm the event in Google Calendar has the correct RRULE.
- [ ] 12.6 Manually create an event "Test import" on the primary calendar; trigger `importCalendarEvents` (or wait for next hourly run); confirm a task appears in Taskr on that date.
- [ ] 12.7 Edit "Test import" on Google's side (change title); after next import run, confirm the task in Taskr reflects the new title.
- [ ] 12.8 Cancel "Test import" on Google's side; after next import, confirm the task is removed.
- [ ] 12.9 Confirm the task created from "Send to Calendar" was NOT re-imported as a duplicate.
- [ ] 12.10 Tap Disconnect; confirm the row returns to "Not connected" and `secrets/{uid}` is empty.
