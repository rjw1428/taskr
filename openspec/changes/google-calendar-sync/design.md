## Context

The user already signs in with Google via `google_sign_in` (native) or `signInWithPopup` (web). Firebase Auth issues a Firebase JWT but does not surface a Google access token usable for Google APIs. To call the Calendar API we need a separate OAuth grant for the `calendar` scope.

The integration is bidirectional:
- **Writes** are user-initiated per-task ("Send to Calendar"). These happen while the app is in the foreground, so the client can call Google directly.
- **Imports** must run hourly even when the app is closed, so they require a server-side path that holds a refresh token.

This combined model (client-side writes + server-side imports) is the simplest split that meets both needs without making the user wait for a cloud function on each write.

Existing infrastructure that this change builds on:
- Firestore at `todos/{uid}` for per-user metadata.
- Cloud Functions v2 with `onSchedule` and `onCall`, and `defineSecret` for OAuth client credentials.
- `tasks/{date}/items/{taskId}` for task documents.

## Goals / Non-Goals

**Goals:**
- Settings page (new) with "Google Calendar" as the first item; connect/disconnect flow.
- Per-task "Send to Calendar" action that writes to the primary calendar with a tag identifying it as ours.
- Recurring tasks render as a single Google event with RRULE.
- Hourly cloud function that imports all events on the primary calendar (except those we wrote) as tasks, using delta sync.
- All Google access on the server uses a refresh token; access tokens are minted per-run and never persisted.

**Non-Goals:**
- Multi-calendar selection (always primary).
- Two-way auto-sync on task edits (manual per-task only).
- Conflict resolution UI when an imported task is edited locally before the next import.
- Cross-calendar moves, attendee management, reminders, attachments.
- Offline queueing of "Send to Calendar" actions.

## Decisions

### Decision: Client + server auth split

Writes use a Google access token obtained client-side via `google_sign_in.requestScopes(['.../calendar'])`. The Calendar API is called from Dart with a plain HTTPS POST.

Imports use a refresh token obtained server-side. On Connect, the client also requests a `serverAuthCode` (`google_sign_in` exposes this via `requestServerAuthCode`); it ships that code to an `exchangeCalendarAuthCode` cloud function, which calls Google's `/token` endpoint with `grant_type=authorization_code` plus our web OAuth client secret to receive a refresh token. The refresh token is written to `todos/{uid}.calendarRefreshToken` via the Admin SDK (bypasses rules).

**Why this split:** the cloud function needs the refresh token to operate when the app is closed. The client doesn't, because re-consent on the app side gives it a fresh access token. Letting the client handle its own access tokens avoids round-trips and keeps writes snappy.

**Alternative considered:** server-only path where the app proxies writes through Firestore. Rejected because the latency on each user tap would be poor (app → Firestore → function → Google → return → Firestore → app).

### Decision: Two OAuth clients in Google Cloud Console

Google's OAuth requires that the `serverAuthCode` exchange happen against a **web-type OAuth client**, not the Android/iOS clients used for `google_sign_in`. So we need:
- Existing Android client (already in use for sign-in).
- A new **web** client; its client ID is configured into `google_sign_in` as `serverClientId` so the consent flow can issue an auth code for it. Its client secret is held by the cloud function via `defineSecret('GOOGLE_OAUTH_CLIENT_SECRET')`.

### Decision: Refresh token field protected by rules

`calendarRefreshToken` lives on `todos/{uid}` but must never be readable by the client. Two options:
- Move it to a parallel collection (`secrets/{uid}.calendarRefreshToken`) protected with `allow read, write: if false;`.
- Keep it on `todos/{uid}` and rely on rule-level field-deny patterns.

Firestore rules can't easily deny reads of a single field on a document the user can otherwise read. So we'll move the secret to `secrets/{uid}` (admin-only) and leave `calendarConnectedAt` on the user's main doc so the client can read connection state.

### Decision: Delta sync via `syncToken`

Initial run for a newly connected user: `events.list(calendarId='primary', timeMin=now, timeMax=now+30d, singleEvents=true)`. Subsequent runs: pass `syncToken=<stored>` (no `timeMin`/`timeMax`). On 410 Gone, clear the stored token and redo the initial fetch.

`singleEvents=true` expands recurring series into individual occurrences. This means a weekly recurring meeting that has 4 occurrences in the window produces 4 imported tasks — one per date.

**Alternative considered:** time-window scan each run (`now → now+30d` every hour). Simpler but ~30× more API quota per run. Delta sync is the right default given hourly cadence.

### Decision: Loop avoidance via `extendedProperties.private.taskrId`

On write, we set `extendedProperties.private.taskrId = <Firestore taskId>`. On import, we skip any event with that key set. Google's Calendar API supports filtering on extended properties (`privateExtendedProperty=taskrId=*`), so we can server-side filter the import query and not even receive our own events — saving processing and avoiding any race window.

### Decision: Task ID stored on imported task

Each imported task carries `calendarEventId = <eventId>`. On subsequent imports, the function looks up tasks by that ID (a small query scoped to `tasks/{eventStartDate}/items` where `calendarEventId == X`). If found, update; else create. If the event status is `cancelled`, delete.

**Note:** this is the only place where Cloud Functions need to write task documents. Existing security rules already allow Admin SDK; no rule changes needed.

### Decision: RRULE generation lives client-side

Recurring tasks today have a custom domain (`GoalFrequency`, `frequencyCount`, etc.). Mapping those to RFC 5545 RRULE strings is a pure function; it lives in `calendar.service.dart` so the write path is self-contained.

Mapping examples:
- Daily → `RRULE:FREQ=DAILY`
- Weekly Mon/Wed/Fri → `RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR`
- Monthly → `RRULE:FREQ=MONTHLY`

### Decision: Settings page is new, not part of the home shell

Currently there's no settings surface. Add `lib/settings/settings_page.dart` and route to it from a gear icon in the app bar (placement to be decided in implementation). The Google Calendar row is the only item for now; the page is structured to accept more rows later.

## Risks / Trade-offs

- **Quota:** Calendar API has per-user and per-project quotas. Hourly delta sync per user is well within limits, even at thousands of users.
- **Refresh token revocation:** if the user revokes access from their Google account settings, the next import errors. We need to detect this (HTTP 400 `invalid_grant`) and clear the stored token, then surface a "reconnect" hint in the app on next open. Implementation includes this in `importCalendarEvents` error handling.
- **Imported tasks have no priority signal.** All imports get `Effort.low`. A future enhancement could parse `event.colorId` or a tag in the title.
- **Time zones.** Events have time zones; tasks use date-only `YYYY-MM-DD`. We use the event's local start date for the `dueDate`, which is correct for the user's primary calendar but could surprise users with cross-timezone events.
- **All-day vs timed events.** All-day events have `start.date`; timed events have `start.dateTime` with a timezone. Both should map to a task on the date portion.
- **Cancelled events with no taskrId.** Imported events that are later cancelled get their task deleted. Manual-write events (with taskrId) that are deleted on Google's side are NOT cleaned up from the task list, since we filter them out of the import. Acceptable for v1.
- **Concurrent imports.** If two scheduled runs overlap (one slow, the next on time), the syncToken from the slower run could be stale when the faster one writes its token. Mitigation: use a per-user transaction or a simple `lastImportRunAt` guard. Implementation will use a transactional update on `calendarSyncToken`.
