## 1. Data Model

- [x] 1.1 Add `reminderTime` (String?) and `reminderTaskName` (String?) fields to the Task model in `lib/services/models.dart`
- [x] 1.2 Run `dart run build_runner build --delete-conflicting-outputs` to regenerate `models.g.dart`

## 2. Cloud Functions — Scheduling & Delivery

- [x] 2.1 Add `@google-cloud/tasks` dependency to `firebase/functions/package.json`
- [x] 2.2 Create callable function `scheduleReminder` that accepts `{ taskId, taskDate, reminderTime, title }`, creates a Cloud Task in the `task-reminders` queue targeting `deliverReminder`, and returns the Cloud Task name
- [x] 2.3 Create callable function `cancelReminder` that accepts `{ reminderTaskName }` and deletes the Cloud Task by name (no-op if already executed or not found)
- [x] 2.4 Create HTTP function `deliverReminder` that receives the payload from Cloud Tasks, verifies the task still exists in Firestore, retrieves the user's FCM token, and sends the FCM message with `data.type = "task_reminder"`

## 3. Reminder Service (Flutter)

- [x] 3.1 Create `lib/services/reminder.service.dart` with methods: `scheduleReminder(Task)`, `cancelReminder(Task)`, and `updateReminder(Task, String newTime)` that call the corresponding callable Cloud Functions and update the task's `reminderTaskName` field in Firestore

## 4. UI — Reminder Picker in Advanced Section

- [x] 4.1 Add reminder date/time picker row to the Advanced `ExpansionTile` in `lib/task_list/add_task.dart`: show "Set reminder" button (or current reminder datetime), date picker → time picker flow, and clear button
- [x] 4.2 Wire up form submission: on save, call `ReminderService.scheduleReminder()` if reminder is new, `updateReminder()` if changed, or `cancelReminder()` if cleared
- [x] 4.3 Update `initiallyExpanded` on the Advanced `ExpansionTile` to also expand when a reminder is set

## 5. In-App Foreground Dialog

- [x] 5.1 In `lib/main.dart` foreground message handler, add a check for `data['type'] == 'task_reminder'` and show an `AlertDialog` with the task title and a "Dismiss" button

## 6. Task Deletion Cleanup

- [x] 6.1 In `TaskService.deleteTask()`, check for `reminderTaskName` on the task and call `cancelReminder` if present before deleting

## 7. Verification

- [ ] 7.1 Set a reminder 2 minutes in the future, close the app, verify FCM notification arrives
- [ ] 7.2 Set a reminder while the app is open, verify in-app dialog popup appears
- [ ] 7.3 Edit a task's reminder to a new time, verify the old Cloud Task is cancelled and a new one is scheduled
- [ ] 7.4 Clear a reminder, verify the Cloud Task is cancelled
- [ ] 7.5 Delete a task with a reminder, verify the Cloud Task is cancelled
