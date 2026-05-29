## Why

Users already sign into Taskr with their Google account, and most already live in Google Calendar for scheduling. Today, there's no bridge between the two:

- Tasks with due dates live only in the app. The user has to mentally reconcile their task list against meetings on their calendar.
- Meetings and events scheduled on the calendar never make it into the task list, so a "what do I need to do today?" view in the app misses everything time-blocked elsewhere.

Adding bi-directional integration with the user's primary Google Calendar lets:
- A user push a specific task (one-shot or recurring) to their calendar with a single tap, so it shows up alongside their meetings.
- The app pull all calendar events back as tasks on an hourly schedule, so today's view in Taskr reflects everything on the calendar — even events created on a laptop minutes ago.

The user is the source of truth for which events become tasks (via the calendar they connect), and we use Google's own metadata (`extendedProperties`) to avoid re-importing events the app itself wrote.

## Capabilities

### New Capabilities

- **calendar-auth** — Settings UI to connect/disconnect Google Calendar. Requests the calendar OAuth scope in addition to the existing sign-in scopes, captures a `serverAuthCode`, exchanges it server-side for a refresh token, and stores that token per-user in Firestore. Connection state is visible in settings; users can revoke.
- **calendar-write** — Per-task "Send to Calendar" action that creates an event on the user's primary Google Calendar from the Flutter app. One-shot tasks become single-occurrence events; recurring tasks become single events with a Google `RRULE`. Every written event is tagged with `extendedProperties.private.taskrId` so it can be identified later.
- **calendar-import** — Hourly Cloud Function that, for every user with a stored refresh token, calls the Google Calendar API with a `syncToken` (or initial window of `now → now + 30d` on first run), and creates a task in Firestore for every event NOT tagged with `taskrId`. Stores the next `syncToken` for delta sync on subsequent runs.

### Modified Capabilities

<!-- None — no existing specs in openspec/specs/. -->

## Impact

- **New code:**
  - Flutter: `lib/settings/` (new directory) for the settings UI; `lib/services/calendar.service.dart` for client-side OAuth + write calls.
  - Cloud Functions: new functions `exchangeCalendarAuthCode` (`onCall`), `importCalendarEvents` (`onSchedule every 60 minutes`), `disconnectCalendar` (`onCall`).
- **Modified code:**
  - `lib/services/auth.service.dart` — extend `GoogleSignIn` scopes to include calendar; expose helper to request incremental scope on demand.
  - `lib/main.dart` or routing — add settings route/icon.
  - `lib/services/task.service.dart` — add a "Send to Calendar" call path; expose import sink that the cloud function writes through Firestore.
- **New dependencies:**
  - Flutter: `googleapis` + `googleapis_auth` (for Calendar API client) or equivalent direct HTTP, similar to how we handle Gemini.
  - Cloud Functions: `googleapis` npm package for server-side Calendar API calls.
- **Firestore schema:**
  - New field: `todos/{uid}.calendarRefreshToken` (string, secret-handled).
  - New field: `todos/{uid}.calendarSyncToken` (string, opaque, rotates per run).
  - New field: `todos/{uid}.calendarConnectedAt` (timestamp).
  - Existing `tasks/{date}/items/{taskId}`: new optional `calendarEventId` field linking back to the Google event.
- **Firestore rules:** `calendarRefreshToken` must be readable/writable only by the Cloud Function (admin SDK bypasses rules; rules should explicitly deny client reads of this field).
- **Google Cloud Console:** requires adding the `https://www.googleapis.com/auth/calendar` scope to the existing OAuth consent screen, and creating a server-side OAuth client (web type) for the code exchange.
- **No UI changes** to existing task list / heatmap / goals — only the new settings area and a new menu item on the task popup.
