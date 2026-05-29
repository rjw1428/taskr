## Context

Taskr is a Flutter/Firebase task management app. Tasks are stored in Firestore at `todos/{userId}/tasks/{date}/items/{taskId}`. The app already has FCM infrastructure: tokens stored per user, `flutter_local_notifications` for foreground display, and foreground message handling via `FirebaseMessaging.onMessage` in `main.dart`. Cloud Functions use `onSchedule` for periodic notifications (goal reminders, train alerts).

The user wants per-task reminders that fire at an exact user-chosen time, delivered as FCM push notifications (background) or in-app dialog popups (foreground).

## Goals / Non-Goals

**Goals:**
- Users can set one reminder (date + time) per task from the Advanced section of the Add/Edit form
- Reminders fire at the exact scheduled time via Cloud Tasks → Cloud Function → FCM
- Foreground users see a dialog popup; background users get a system notification
- Changing or deleting a task cancels the scheduled reminder
- Changing the reminder time reschedules it

**Non-Goals:**
- Multiple reminders per task
- Recurring reminders (snooze/repeat)
- Reminder templates or default reminder offsets
- iOS-specific notification configuration (Android-only for now)

## Decisions

### 1. Delivery mechanism: Cloud Tasks (not polling)

Use GCP Cloud Tasks to schedule exact-time delivery rather than a per-minute Cloud Function poll.

**How it works:**
1. When a user sets a reminder, the Flutter app calls a callable Cloud Function `scheduleReminder`
2. That function creates a Cloud Task targeting an HTTP Cloud Function `deliverReminder` with the scheduled time
3. At the scheduled time, Cloud Tasks invokes `deliverReminder`, which sends the FCM message
4. The task document stores a `reminderTaskName` field (the Cloud Tasks task name) for cancellation

**Why not polling:** A per-minute function would run 1,440 times/day regardless of reminder count. Cloud Tasks costs nothing for scheduling and fires exactly once per reminder.

**Alternatives considered:**
- Per-minute poll: simpler but expensive and imprecise
- `flutter_local_notifications` scheduled locally: doesn't work when app is killed, unreliable on Android with battery optimization

### 2. Data model: single `reminderTime` ISO string on Task

Add one field to the Task model:
- `String? reminderTime` — full ISO 8601 datetime string (e.g., `"2026-05-28T14:30:00"`)

And one internal field for cancellation:
- `String? reminderTaskName` — the Cloud Tasks task resource name, not exposed in UI

**Why a single ISO string:** Combines date and time in one field. Since the task already has a `dueDate`, the reminder date can differ (e.g., remind the day before). Storing the full datetime avoids timezone ambiguity.

### 3. Cloud Tasks queue setup

- Queue name: `task-reminders`
- Region: `us-central1` (same as Cloud Functions)
- Target: HTTP Cloud Function `deliverReminder`
- Payload: `{ userId, taskId, taskDate, title }`

### 4. In-app dialog for foreground alerts

Reuse the existing `FirebaseMessaging.onMessage` listener in `main.dart`. When a message with `data.type == "task_reminder"` arrives, show an `AlertDialog` with the task title and a dismiss button. This follows the existing pattern used for wind alerts (lines 94-161 in `main.dart`).

### 5. Cancellation flow

When a task's reminder changes or the task is deleted:
1. Read `reminderTaskName` from the task document
2. Call a callable function `cancelReminder` that deletes the Cloud Task by name
3. If rescheduling, call `scheduleReminder` with the new time

## Risks / Trade-offs

- **[Cloud Tasks API must be enabled]** → Requires one-time GCP Console setup: enable the API and create the `task-reminders` queue. Document this in deployment steps.
- **[Clock skew]** → Cloud Tasks guarantees delivery within a few seconds of the scheduled time. Acceptable for this use case.
- **[Task deletion without cancellation]** → If a task is deleted but the cancellation call fails, the Cloud Task fires and `deliverReminder` can't find the task. Mitigation: `deliverReminder` checks if the task still exists before sending; silently no-ops if gone.
- **[Orphaned Cloud Tasks]** → If `reminderTaskName` is lost (e.g., Firestore write fails after scheduling), the Cloud Task fires but the task still exists — user just gets an extra notification. Low severity.
- **[Service account permissions]** → Cloud Functions need `cloudtasks.tasks.create` and `cloudtasks.tasks.delete` permissions. The default App Engine service account typically has these.
