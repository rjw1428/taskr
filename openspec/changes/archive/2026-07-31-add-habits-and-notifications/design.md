## Context

taskr stores tasks in date-partitioned collections (`todos/{uid}/tasks/{YYYY-MM-DD}/items/{taskId}`, `"unassigned"` for backlog, each task carrying a denormalized `userId`). Recurring tasks are generated via RRULE helpers in `task.service.dart` (`_buildRecurrenceRule`, `_generateRecurringTaskInstances`, `getRecurrenceFrequency`, `getWeeklyRecurrenceList`) from a `RecurringTask` template with a **required endDate**, capped at ~30 instances; the generation block is also duplicated inline in `add_task.dart`. Completion scoring runs in the `task_item.dart` checkbox via `PerformanceService.getScore` (high=3/med=2/low=1/info=0). Denormalized counters maintained transactionally + a recompute drift-recovery method are an established pattern (`childCount`/`toggleSubtaskComplete`/`recomputeParentCounters`), as is collection-group reads scoped by `userId` (`streamSubtasks`, backed by the `(userId, parentId)` index + `/{path=**}/items/{itemId}` rule). Goals live in `goals/` (`streamGoals`, `addGoal`, pause/resume/delete). FCM sends happen at five sites in `firebase/functions/src/index.ts`.

## Goals / Non-Goals

**Goals:**
- Manual habits in the Goals tab that reuse recurring generation; per-instance streak display; Effort scoring that never counts the streak.
- Open-ended habits via rolling top-up (no giant up-front materialization).
- Persist and review sent FCM notifications; unread badge.
- All-time Records card on Performance.

**Non-Goals:**
- No AI for habits (that's what distinguishes them from goals).
- No change to the core scoring formula, recurring tasks, calendar, Garmin, people.
- No streak multipliers/bonuses feeding the score.
- No new prominent "today's score" hero on Performance (user chose to keep current) — only the Records card is added.

## Decisions

### D1: Habits are a separate `todos/{uid}/habits` collection + a `Task.habitId` stamp (not reuse `recurring`)
`RecurringTask` machinery assumes a finite endDate (form `validate()` requires it; series expansion walks the whole range toward the `take(1000)` cap) and drives the "View Series"/recurring-delete UI keyed on `recurringTemplateId`. Habits are open-ended and should not surface that UI. So habits get their own template collection and instances are stamped with `habitId`. We still **reuse the RRULE helpers** by converting a `Habit` to a bounded `RecurringTask` on the fly (`_toRecurringTask(habit, until: horizon)`).
- **Alternative rejected:** reuse `recurringTemplateId` + an `isHabit` flag — entangles two lifecycles and the recurring-delete/series UI.

### D2: Open-ended lifespan via rolling client-side top-up
`HabitService.ensureInstances(habit, horizonDays: 60)` generates only the missing scheduled dates from `lastMaterializedDate+1` to `today+60`, reusing the RRULE helpers + `TaskService.addTask` (which handles ordering + `userId`). Invoked on habit create, on Habits-list build, and on the List tab load. Idempotent (existence check + `lastMaterializedDate` guard).
- **vs. long endDate + full materialization:** thousands of docs up front, `taskOrder` bloat, slow deletes.
- **vs. scheduled Cloud Function:** adds a deploy/cost/second-codepath; the app is already client-authoritative for task generation.
- **Tradeoff:** a user idle >60 days won't have instances past the horizon; self-heals on next open (acceptable — streaks are about engagement).

### D3: Streak is a maintained counter, recomputed authoritatively; never affects score
Stored on the habit doc: `currentStreak`, `longestStreak`, `lastCompletedDate`. `recomputeStreak(habit)` runs one collection-group query (`items where userId==uid and habitId==h.id`), builds `completedByDate`, generates scheduled dates from `startDate` via the rule, and walks backward from the most recent scheduled occurrence (treating *today, if not yet done*, as "pending" not "missed") counting consecutive completed occurrences until the first miss. Called from `TaskService.toggleHabitComplete` (parallel to `toggleSubtaskComplete`) and opportunistically on screen load. Full recomputation (not incremental) → robust to un-complete and back-dated edits, exactly like `recomputeParentCounters`.
- **Card liveness guard (O(1), no query):** since the stored value reflects the last toggle, at render time compute the most recent past scheduled date; if it's after `lastCompletedDate`, a scheduled occurrence lapsed uncompleted → display 0; else display `currentStreak`.
- **Scoring:** habit instances carry `priority = habit.effort` and score through the unchanged `PerformanceService` path in the card. The streak touches nothing in scoring.
- Requires a `(userId, habitId)` collection-group index (mirrors `(userId, parentId)`); the existing `/{path=**}/items/{itemId}` rule already authorizes it.

### D4: Notification capture is backend-on-send
A shared `recordNotification(uid, {title, body, data, type})` helper in `functions/src/index.ts` writes `todos/{uid}/notifications/{id}` (`{title, body, data, type, sentAt: epoch-ms, read:false}`), called immediately after each `admin.messaging().send(...)` at the five send sites (`executeTrainNotification`, `sendMessage`, `sendGoalReminder`, `generateWeeklyTasksForGoal`, `deliverReminder`). Wrapped in try/catch so logging never breaks the send. `sentAt` is epoch-ms (matches `Task.added`/`Goal.createdAt` int convention, avoids `Timestamp` codegen friction). No new security rule (under `todos/{uid}`). App side: `NotificationService` (`streamNotifications` ordered by `sentAt` desc with `.limit(100)`, `unreadCount` via `where(read==false)`, `markRead`/`markAllRead`/`delete`/`clearAll`), a Notification Center screen, an overflow-menu entry + Material 3 `Badge` unread count. **Requires a functions deploy.**

### D5: Performance Records card (all-time, persisted)
- **Highest daily score:** derived from the existing per-day performance docs (`completed.ALL`). Computed by scanning performance history (the Performance tab already streams a window; for all-time, either scan all performance docs on card load or maintain a small `todos/{uid}/stats` record doc updated when a day's score changes). Show value + date.
- **Longest streak:** the max `longestStreak` across habits, with the habit's name + `lastCompletedDate`. Read from the streamed habits.
- Rendered as an `AppCard` "Records" section at the bottom of `performance_page.dart`, styled with the design tokens; room for a couple more basic stats (e.g., total tasks completed, count of active streaks).

## Risks / Trade-offs

- **Timezone/day boundary:** all streak generation + `today` comparisons must use local `yyyy-MM-dd` via `DateService.getString`; convert RRULE (UTC) outputs back through it, as `_addRecurringTask` already does.
- **Rolling top-up races/dupes:** existence check before `addTask` + `lastMaterializedDate` guard.
- **Index build lag:** the `(userId, habitId)` query errors until the index finishes; reuse the `Rx.retryWhen` self-heal pattern if it's ever a stream.
- **Notification growth:** cap `streamNotifications` at 100 + "Clear all"; a TTL cleanup function is out of scope.
- **Deploy dependencies:** notification capture needs a functions deploy; the habit streak query needs the new index deployed. Until then, the notification center shows empty (no crash) and the streak query self-heals when the index is ready.
- **Effort changes** on an existing habit apply only to future instances (past scoring already recorded).

## Migration Plan
1. Models (`Habit`, `AppNotification`, `Task.habitId`) + `build_runner`; add `(userId, habitId)` index.
2. `HabitService` (CRUD, `ensureInstances`, `recomputeStreak`) + `TaskService.toggleHabitComplete`; centralize the RRULE generator.
3. Habits UI (Goals-tab section, `habit_form.dart`, FAB chooser) + streak badge/completion routing in `task_item.dart`.
4. `NotificationService` + Notification Center screen + route + overflow menu/badge.
5. `recordNotification` + five send-site calls in functions; user deploys functions + indexes.
6. Performance Records card.

**Rollback:** additive collections/fields/screens; revert per-commit. Backend change is additive (only writes new docs).

## Open Questions
- Highest-score storage: scan-on-load vs. a maintained `stats` doc — decide during implementation based on how many performance docs exist (scan is fine for a personal app).
- Whether to add pause/delete via a habit detail page vs. an inline menu on the habit card (lean inline to keep scope small).
