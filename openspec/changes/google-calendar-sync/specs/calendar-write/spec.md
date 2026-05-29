## ADDED Requirements

### Requirement: Task popup menu offers "Send to Calendar"

Each task in the task list SHALL expose a "Send to Calendar" action in its popup menu, enabled only when the user has a connected calendar and the task has a `dueDate`. The action MUST be hidden (not just disabled) when no calendar is connected.

#### Scenario: Action visible
- **WHEN** the user has connected a calendar and views a task with a due date
- **THEN** the popup menu includes a "Send to Calendar" action

#### Scenario: Action hidden when not connected
- **WHEN** the user has not connected a calendar
- **THEN** the "Send to Calendar" action is absent from the popup menu

#### Scenario: Action hidden when no due date
- **WHEN** the task has no `dueDate`
- **THEN** the action is absent regardless of connection state

### Requirement: One-shot task becomes a single calendar event

For a non-recurring task, tapping "Send to Calendar" SHALL create a Google Calendar event on the user's primary calendar with:
- `summary` = task title
- `description` = task description (if present)
- `start.date` and `end.date` = the task's `dueDate` (all-day event)
- `extendedProperties.private.taskrId` = the task's Firestore ID

The returned `eventId` MUST be stored back on the task as `calendarEventId`.

#### Scenario: Create one-shot event
- **WHEN** the user taps "Send to Calendar" on a task due 2026-05-20 with title "Renew passport"
- **THEN** an all-day event is created on their primary calendar for 2026-05-20 titled "Renew passport"
- **AND** the event carries `extendedProperties.private.taskrId = <taskId>`
- **AND** the task's Firestore document gains `calendarEventId = <eventId>`

#### Scenario: Already sent
- **WHEN** the user taps "Send to Calendar" on a task that already has a `calendarEventId`
- **THEN** the existing event is updated rather than duplicated
- **AND** the task's `calendarEventId` remains the same

### Requirement: Recurring task becomes a single event with RRULE

For a recurring task (one whose schedule is defined by a recurring template), "Send to Calendar" SHALL create a single Google Calendar event with a `recurrence` field containing an RRULE that matches the task's pattern. The RRULE MUST express at least the frequency (daily, weekly, monthly) and the day(s) of the week where applicable.

#### Scenario: Daily recurring task
- **WHEN** the user sends a recurring task with daily frequency
- **THEN** the event's `recurrence` contains `RRULE:FREQ=DAILY`

#### Scenario: Weekly N-times recurring task
- **WHEN** the user sends a recurring task scheduled for Monday/Wednesday/Friday
- **THEN** the event's `recurrence` contains `RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR`

### Requirement: Calendar events written by the app are tagged

Every event the app creates SHALL include `extendedProperties.private.taskrId = <taskId>` so it can be identified later during import.

#### Scenario: Tag is present
- **WHEN** any event is written via the calendar-write capability
- **THEN** that event's `extendedProperties.private.taskrId` is set to the originating task's Firestore ID

### Requirement: Send failures surface to the user

If the Calendar API call fails (network, auth, quota), the app SHALL show a transient error message and MUST NOT store a `calendarEventId` on the task.

#### Scenario: Auth token expired
- **WHEN** the access token is expired or invalid at send time
- **THEN** the app attempts a silent re-auth once
- **AND** if the retry fails, shows "Could not send to calendar — please reconnect in Settings"

#### Scenario: Network error
- **WHEN** the request fails with a network error
- **THEN** the app shows "Couldn't reach Google Calendar" and the task is unchanged
