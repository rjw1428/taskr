# Implementation Tasks: Habits & Notifications

## 1. Data Model & Index

- [x] 1.1 Add `Habit` model to `models.dart` (id, title, effort, recurrenceType, frequency, daysOfWeek, dayOfMonth, startDate, reminderTime, status, currentStreak, longestStreak, lastCompletedDate, lastMaterializedDate, createdAt, modifiedAt)
- [x] 1.2 Add `String? habitId` to `Task` (constructor, copyWith, serialization)
- [x] 1.3 Add `AppNotification` model (id, title, body, data, type, sentAt, read)
- [x] 1.4 Regenerate `models.g.dart` (`build_runner`)
- [x] 1.5 Add `(userId, habitId)` collection-group index to `firestore.indexes.json` (mirrors the `(userId, parentId)` index)

## 2. Habit Service & Generation

- [ ] 2.1 Create `HabitService` (+ barrel export in `services.dart`): `habitCollection`, `streamHabits`, `getHabit`
- [ ] 2.2 `_toRecurringTask(habit, {until})` — convert a habit to a bounded `RecurringTask` so existing RRULE helpers apply
- [ ] 2.3 Centralize instance generation in `TaskService` (extract the inline RRULE block from `add_task.dart`) into a reusable generator
- [ ] 2.4 `ensureInstances(habit, horizonDays: 60)` — rolling top-up: generate only missing scheduled dates via the helpers + `addTask`, guard on `lastMaterializedDate` + existence
- [ ] 2.5 `addHabit`, `updateHabit` (delete future incomplete instances + re-ensure), `pauseHabit`/`resumeHabit`, `deleteHabit`
- [ ] 2.6 `recomputeStreak(habit)` — collection-group query `items where userId==uid and habitId==h.id`; backward-walk scheduled occurrences (today pending, not missed); set currentStreak/longestStreak/lastCompletedDate
- [ ] 2.7 `TaskService.toggleHabitComplete(instance, completed)` — update instance + call `recomputeStreak`; scoring stays in the card

## 3. Habits UI

- [ ] 3.1 `habit_form.dart` — title, cadence (reuse `RecurringTaskForm` with an optional `hideEndDate` flag), Effort segmented control, optional reminder time
- [ ] 3.2 Habits section in `goal_list.dart` — `StreamBuilder<List<Habit>>`, `_HabitCard` (flame icon, title, cadence + 🔥 streak with liveness guard, inline pause/delete menu), call `ensureInstances` on build
- [ ] 3.3 FAB chooser in `home.dart` case 2 (Goals tab): "New Goal" / "New Habit"
- [ ] 3.4 `task_item.dart` — streak badge (🔥 N) on habit instances; route habit completion through `toggleHabitComplete`; pass a `habitStreaks` map from the list screen (default `{}`)
- [ ] 3.5 Wire the List/Goals screens to stream habits and supply the streak map to `TaskItem`

## 4. Notification Center (app)

- [ ] 4.1 `NotificationService` (+ barrel export): `streamNotifications` (orderBy sentAt desc, limit 100), `unreadCount` (where read==false), `markRead`, `markAllRead`, `delete`, `clearAll`
- [ ] 4.2 `notification_center.dart` — list (title/body/relative time/read state), Dismissible delete, mark-all-read + clear-all actions, `EmptyState`
- [ ] 4.3 Add relative-time helper to `DateService` ("5m ago" etc.)
- [ ] 4.4 Register `/notifications` route in `main.dart`
- [ ] 4.5 `home.dart` overflow menu: add "Notifications" item + navigate; wrap the menu icon in a `Badge` driven by `unreadCount`

## 5. Notification Capture (backend — requires deploy)

- [ ] 5.1 Add `recordNotification(uid, {title, body, data, type})` helper in `functions/src/index.ts` (try/catch; writes `todos/{uid}/notifications` with sentAt epoch-ms, read:false)
- [ ] 5.2 Call it after each FCM send: `executeTrainNotification`, `sendMessage`, `sendGoalReminder`, `generateWeeklyTasksForGoal`, `deliverReminder`
- [ ] 5.3 User deploys: `firebase deploy --only functions`

## 6. Performance Records Card

- [ ] 6.1 Compute all-time highest daily score (+ date) from performance history (scan, or a maintained `stats` doc)
- [ ] 6.2 Compute longest streak (+ habit name + last-completed date) from streamed habits
- [ ] 6.3 Render a "Records" `AppCard` at the bottom of `performance_page.dart` (highest score, longest streak, room for a couple more basic stats); graceful empty values

## 7. Verification

- [ ] 7.1 Create daily + day-of-week habits; verify instances appear on scheduled days with the streak badge
- [ ] 7.2 Complete/miss occurrences; verify streak increments and resets per the rules; verify score reflects Effort only (streak adds nothing)
- [ ] 7.3 Pause/resume/delete a habit; verify completed history is preserved
- [ ] 7.4 Deploy functions + index; verify notifications are captured and listed, unread badge works, mark-read/clear behave
- [ ] 7.5 Verify the Records card shows correct all-time highest score + longest streak
- [ ] 7.6 Verify existing tasks/recurring tasks/goals are unaffected
