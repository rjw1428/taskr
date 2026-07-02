## Why

Some tasks are tied to a fixed future date (a trip, an exam, a renewal deadline) and the user wants an at-a-glance sense of how much time is left, without opening the task or navigating to its day. The task list currently only shows one day at a time, so a future-dated task is invisible until you page to its due date.

## What Changes

- Add a new **"Countdown"** toggle to the Advanced section of the task create/edit form.
- Persist a `countdown` boolean on the `Task` model.
- When enabled, the task is surfaced as a small **chip** ("⏳ 45d Passport") in a wrapping row at the top of the task list day view, directly **above** the day's points (`DailyProgress`).
- Countdown chips are **global**: they appear in the header on every day you view, not just the task's own day. Each chip shows the number of days from the **currently viewed day** to the task's **due date**.
- Chips **disappear** once the countdown reaches zero (viewed day is on or after the due date).
- Multiple chips share a single row and wrap to additional rows only when they overflow the width.
- Chips use the app's purple accent — sourced from `Theme.of(context).colorScheme.primary` (the same default that colors the task-list add button), not a hardcoded value.
- Introduce a lightweight per-user `countdowns` index collection so the day view can stream the small set of countdown tasks across all days without expensive cross-day reads or a data migration.

## Capabilities

### New Capabilities
- `task-countdown`: Marking a task as a countdown and rendering days-until-due chips in the task list header across day views.

### Modified Capabilities
<!-- No existing spec files under openspec/specs/ cover task creation or the task list; no requirement-level changes to existing capabilities. -->

## Impact

- **Model:** `lib/services/models.dart` (+ `models.g.dart`) — new `bool countdown` field on `Task` (constructor, `copyWith`, JSON serialization).
- **Form:** `lib/task_list/add_task.dart` — new `_countdown` state, a toggle in the Advanced `ExpansionTile`, and passing the value into all `Task` construction sites (single, recurring, multi-day).
- **Task list:** `lib/task_list/task_list.dart` + `lib/shared/progress_bar.dart` — a new wrapping chip row inserted above `DailyProgress` in the list header.
- **Service:** `lib/services/task.service.dart` — maintain the `countdowns` index on task add/update/complete/delete, and expose a stream of countdown entries for the current user.
- **Firestore:** new subcollection `todos/{uid}/countdowns/{taskId}` storing `{ title, dueDate }`.
- No Cloud Functions changes. No breaking changes; `countdown` defaults to `false` so existing tasks are unaffected.
