## ADDED Requirements

### Requirement: Hourly scheduled function imports calendar events

A Cloud Function `importCalendarEvents` SHALL run on a schedule of `every 60 minutes`. On each run, it MUST iterate over every user document in `todos/` that has a non-empty `calendarRefreshToken` and process them in parallel-safe batches.

#### Scenario: Skips disconnected users
- **WHEN** the function runs and a user has no `calendarRefreshToken`
- **THEN** that user is skipped without any API call

#### Scenario: Continues on per-user failure
- **WHEN** the function fails to process one user (e.g., revoked token)
- **THEN** it logs the error and continues with the remaining users

### Requirement: Per-user delta sync via syncToken

For each connected user, the function SHALL use the stored `calendarSyncToken` to fetch only events changed since the last run. If no syncToken exists (first run or after a 410 Gone response), the function MUST do an initial fetch of events from `now` through `now + 30 days` to seed the sync. The new `nextSyncToken` returned by Google MUST be stored back on the user document.

#### Scenario: Subsequent run with valid syncToken
- **WHEN** the function runs for a user with a stored syncToken
- **THEN** it calls `events.list` with that syncToken
- **AND** processes only events returned by that delta
- **AND** stores the new `nextSyncToken` from the response

#### Scenario: First run for newly connected user
- **WHEN** the function runs for a user with no stored syncToken
- **THEN** it calls `events.list` with `timeMin = now` and `timeMax = now + 30d`
- **AND** processes the returned events
- **AND** stores the `nextSyncToken` from the response

#### Scenario: Stale syncToken
- **WHEN** Google returns 410 Gone for an expired syncToken
- **THEN** the function clears `calendarSyncToken` and performs an initial fetch as if the user just connected

### Requirement: Skip events the app itself wrote

When importing, the function SHALL skip any event whose `extendedProperties.private.taskrId` is set. These events were created by the calendar-write capability and already correspond to a task in Firestore.

#### Scenario: Skip tagged event
- **WHEN** the function receives an event with `extendedProperties.private.taskrId = "abc123"`
- **THEN** that event is not imported as a new task

#### Scenario: Import untagged event
- **WHEN** the function receives an event without the `taskrId` property
- **THEN** it imports the event as a task

### Requirement: Event-to-task mapping

For each imported event, the function SHALL create a task in Firestore under `tasks/{date}/items/` for the event's start date with:
- `title` = event `summary` (or "Untitled" if missing)
- `description` = event `description` (if present)
- `dueDate` = event start date in `YYYY-MM-DD` form (local time of the event)
- `priority` = `low` (Effort.low) by default
- `completed` = false
- `added` = current epoch ms
- `calendarEventId` = the imported event's ID
- `tags` = empty list

If a task with the same `calendarEventId` already exists, the function MUST update that task instead of creating a duplicate.

#### Scenario: New event imported as task
- **WHEN** the function imports an untagged event "Dentist" starting 2026-05-14T14:00
- **THEN** a task is created at `tasks/2026-05-14/items/<newId>` with title "Dentist" and `calendarEventId` set

#### Scenario: Updated event updates existing task
- **WHEN** the function receives an updated event with `id = "evt-99"` and a task with `calendarEventId = "evt-99"` exists
- **THEN** that task's title, description, and dueDate are updated
- **AND** no new task is created

#### Scenario: Deleted event removes imported task
- **WHEN** the function receives an event with `status = "cancelled"` and a task with the matching `calendarEventId` exists
- **THEN** the task is deleted from Firestore

### Requirement: Recurring events expand to single tasks per occurrence

When the API returns a recurring event series within the import window, the function SHALL use `singleEvents=true` so that each occurrence is returned individually. Each occurrence is then imported as its own task (with the same originating event treated as one task per date).

#### Scenario: Weekly recurring event
- **WHEN** the import window contains a weekly recurring event with 4 occurrences
- **THEN** 4 tasks are created, one per occurrence date

### Requirement: Access token derivation uses stored refresh token

The function SHALL use the per-user `calendarRefreshToken` plus the server-side OAuth client credentials to mint a fresh access token at the start of each user's processing. The access token MUST NOT be persisted.

#### Scenario: Token minting
- **WHEN** the function processes a user
- **THEN** it exchanges the refresh token for an access token via Google's OAuth token endpoint
- **AND** uses that access token for all API calls for that user during the run
- **AND** does not store the access token in Firestore
