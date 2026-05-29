## Why

Tasks currently have no way to alert the user at a specific time. Users must remember to check the app or rely on generic daily goal reminders. A per-task reminder lets users set a precise date/time alert so time-sensitive tasks (appointments, deadlines, calls) aren't missed.

## What Changes

- Add an optional reminder (date + time) field to tasks, editable from the "Advanced" section of the Add/Edit Task form
- When a reminder is set, schedule a one-shot Cloud Task that fires an FCM notification at the exact time
- When the app is in the foreground, show an in-app dialog popup instead of (or in addition to) the system notification
- When a reminder time or task is changed/deleted, cancel and optionally reschedule the Cloud Task
- Add a `cloud_tasks` dependency to the Firebase Cloud Functions

## Capabilities

### New Capabilities
- `task-reminders`: Scheduling, delivering, and managing per-task reminder alerts via Cloud Tasks + FCM, including the Flutter UI for setting reminder date/time and the in-app dialog for foreground alerts

### Modified Capabilities

None — no existing specs to modify.

## Impact

- **Flutter app**: Task model gains `reminderTime` field; Add/Edit form gets reminder date+time picker in Advanced section; `main.dart` foreground handler needs to show reminder-specific dialog
- **Cloud Functions**: New callable functions to schedule/cancel Cloud Tasks; new HTTP endpoint invoked by Cloud Tasks to send FCM
- **Firebase/GCP**: Requires enabling the Cloud Tasks API and creating a queue in the project
- **Dependencies**: `@google-cloud/tasks` npm package in cloud functions
