## Why

taskr is becoming a lifestyle/self-improvement tool: tasks, goals, performance scoring, journaling, a relationship CRM, and Garmin health. Two things are missing that round it out:

1. **Habits & streaks** — a manual, lightweight way to build consistent routines. Recurring tasks exist, but they don't give the "don't break the chain" streak motivation that drives habit formation. Habits should feel gamified and feed the daily score modestly, but **streaks must not dominate scoring** — the daily high score stays driven by real task output.
2. **A notification center** — FCM notifications (goal reminders, task reminders, train/goal-tasks alerts) currently vanish after they're shown. Users want to review and clear past notifications from the top-right menu.

Plus a small gamification touch: a **Records** card on the Performance tab (highest daily score, longest streak).

## What Changes

- **Habits** live in the **Goals tab** as a sibling to goals; creation is manual (no AI). A habit is backed by the existing recurring-task machinery — it materializes real task instances on a cadence (daily / weekly / day-of-week / monthly).
- Each habit task instance shows its **current streak** (🔥 N) on the task card. Completing a habit's instance scores its Effort points through the **existing** completion flow (default Effort = Low = 1 pt, adjustable per habit). **The streak is a separate consistency badge that never affects the score.**
- Habits are **open-ended** (no end date), materialized via a **rolling client-side top-up** that keeps the next ~60 days of instances filled.
- **Notification center**: every Cloud Function that sends an FCM message also writes a notification record to Firestore; the app lists them (read/unread, mark-read, delete, clear-all) on a new screen reached from the upper-right overflow menu, with an unread-count badge. **BREAKING/OPS:** requires a Cloud Functions deploy.
- **Performance Records card**: a stats card at the bottom of the Performance tab showing all-time **highest daily score** (+ date) and **longest streak** (+ habit name + last-completed date), plus room for a couple more basic stats.

## Capabilities

### New Capabilities
- `habits-and-streaks`: manual habits in the Goals tab backed by recurring-task generation, open-ended rolling materialization, per-instance streak display, streak computation/reset semantics, and Effort-based scoring that keeps streaks out of the score.
- `notification-center`: persistence of sent FCM notifications (backend-on-send), and an in-app center to review/mark-read/clear them with an unread badge.
- `performance-records`: an all-time records/stats card on the Performance tab (highest daily score, longest streak).

### Modified Capabilities
<!-- No existing OpenSpec specs define these areas at requirement level. -->

## Impact

- **Data model** (`lib/services/models.dart`): new `Habit` and `AppNotification` models; `Task` gains `habitId`. Regenerate `models.g.dart`.
- **Services**: new `HabitService` and `NotificationService`; `TaskService` gains `toggleHabitComplete` and a reusable instance generator (centralizing the RRULE block currently duplicated in `add_task.dart`).
- **UI**: Habits section + form in the Goals tab (`goals/`), streak badge + habit completion routing in `task_list/task_item.dart`, a Habit/Goal FAB chooser in `home.dart`, a Notification Center screen + overflow-menu entry + unread badge in `home.dart`, a Records card in `performance/`.
- **Backend** (`firebase/functions/src/index.ts`): a `recordNotification` helper called at the five FCM send sites. Requires `firebase deploy --only functions`.
- **Firestore**: new `habits` and `notifications` subcollections under `todos/{uid}` (covered by the existing owner rule — no new rule). One new collection-group index `(userId, habitId)` on `items` (mirrors the existing `(userId, parentId)` index); requires `firebase deploy --only firestore:indexes`.
- **No changes** to auth, calendar, Garmin, people, or the redesign. Existing tasks/recurring tasks behave unchanged.
