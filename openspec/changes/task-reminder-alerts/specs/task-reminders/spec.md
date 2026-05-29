## ADDED Requirements

### Requirement: User can set a reminder on a task
The system SHALL allow the user to set an optional reminder date and time on any task from the Advanced section of the Add/Edit Task form. The reminder SHALL consist of a single date and time. The reminder field SHALL be clearable.

#### Scenario: Setting a reminder on a new task
- **WHEN** the user creates a task and selects a reminder date and time in the Advanced section
- **THEN** the task is saved with the `reminderTime` field set to the selected ISO 8601 datetime

#### Scenario: Setting a reminder on an existing task
- **WHEN** the user edits a task and adds or changes the reminder date and time
- **THEN** the task's `reminderTime` field is updated and any previously scheduled alert is cancelled and rescheduled

#### Scenario: Clearing a reminder
- **WHEN** the user edits a task and clears the reminder field
- **THEN** the task's `reminderTime` field is set to null and the scheduled alert is cancelled

### Requirement: Reminder is scheduled via Cloud Tasks
The system SHALL schedule a one-shot GCP Cloud Task when a reminder is set. The Cloud Task SHALL target an HTTP Cloud Function that delivers the notification at the exact scheduled time.

#### Scenario: Scheduling on reminder set
- **WHEN** a task is saved with a non-null `reminderTime`
- **THEN** the app calls a callable Cloud Function `scheduleReminder` which creates a Cloud Task scheduled for that time, and stores the Cloud Task name in the task's `reminderTaskName` field

#### Scenario: Rescheduling on reminder change
- **WHEN** a task's `reminderTime` is changed to a different non-null value
- **THEN** the previous Cloud Task is cancelled using `reminderTaskName` and a new Cloud Task is created for the updated time

#### Scenario: Cancelling on reminder clear or task delete
- **WHEN** a task with a scheduled reminder is deleted or its `reminderTime` is set to null
- **THEN** the Cloud Task identified by `reminderTaskName` is deleted

### Requirement: Reminder delivers FCM notification
The system SHALL send an FCM push notification to the user's device when a reminder fires. The notification SHALL include the task title. The `deliverReminder` Cloud Function SHALL verify the task still exists before sending.

#### Scenario: Delivering a reminder for an existing task
- **WHEN** the Cloud Task fires and the target task still exists in Firestore
- **THEN** the system sends an FCM message with `notification.title` = "Reminder" and `notification.body` = the task title, and `data.type` = "task_reminder"

#### Scenario: Delivering a reminder for a deleted task
- **WHEN** the Cloud Task fires but the target task no longer exists in Firestore
- **THEN** the system silently discards the reminder without sending a notification

### Requirement: In-app dialog for foreground reminders
The system SHALL display an AlertDialog popup when a reminder notification arrives while the app is in the foreground. The dialog SHALL show the task title and a dismiss button.

#### Scenario: Reminder arrives while app is in foreground
- **WHEN** the app is in the foreground and receives a message with `data.type == "task_reminder"`
- **THEN** an AlertDialog is displayed with the task title and a "Dismiss" button

#### Scenario: Reminder arrives while app is in background
- **WHEN** the app is in the background or closed and a reminder FCM is received
- **THEN** the system notification is displayed via the default FCM notification channel

### Requirement: Reminder UI in Advanced section
The system SHALL display a reminder date/time picker in the Advanced ExpansionTile of the Add/Edit Task form. The picker SHALL only be visible when a due date is set. The reminder datetime picker SHALL default to the task's due date if no reminder is currently set.

#### Scenario: Showing the reminder picker
- **WHEN** the user opens the Advanced section and a due date is set
- **THEN** a "Set reminder" button is displayed, or the current reminder date/time if one is already set

#### Scenario: Selecting a reminder date and time
- **WHEN** the user taps the reminder button
- **THEN** a date picker is shown defaulting to the task's due date, followed by a time picker, and the selected datetime is stored as the reminder

#### Scenario: Changing the reminder date to a different day
- **WHEN** the user selects a date different from the due date in the reminder date picker
- **THEN** the reminder is scheduled for the selected date and time, allowing reminders before or after the due date

#### Scenario: Reminder not available without due date
- **WHEN** the task has no due date set
- **THEN** the reminder option is not shown in the Advanced section
