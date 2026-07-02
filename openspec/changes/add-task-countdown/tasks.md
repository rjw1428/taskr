## 1. Data model

- [x] 1.1 Add `bool countdown` field (default `false`) to the `Task` class in `lib/services/models.dart` — constructor param, field, and `copyWith`.
- [x] 1.2 Update `lib/services/models.g.dart` so `_$TaskFromJson` reads `countdown` (defaulting to `false` when absent) and `_$TaskToJson` writes it. Alternatively regenerate with build_runner.
- [x] 1.3 Confirm `toDbTask()` includes the new field (it derives from `toJson()`), so `countdown` is persisted on the task document.

## 2. Countdown index in TaskService

- [x] 2.1 Add a `countdownCollection(String userId)` helper in `lib/services/task.service.dart` pointing at `todos/{uid}/countdowns`.
- [x] 2.2 Add a private `_syncCountdownIndex(userId, task)` that upserts `{ title, dueDate }` at `countdowns/{taskId}` when `task.countdown == true` and `task.dueDate != null`, and deletes the doc otherwise.
- [x] 2.3 Call `_syncCountdownIndex` from the task add and update write paths.
- [x] 2.4 Delete the countdown index doc when a task is completed and when it is deleted.
- [x] 2.5 Add a `streamCountdowns(userId)` method returning a stream of countdown entries (taskId, title, dueDate) from `todos/{uid}/countdowns`.

## 3. Advanced-options toggle (add/edit form)

- [x] 3.1 In `lib/task_list/add_task.dart`, declare `bool _countdown = false` state and initialize it from `widget.task?.countdown` in `initState`.
- [x] 3.2 Add a Countdown toggle Row inside the "Advanced" `ExpansionTile`, mirroring the existing recurring/multi-day checkbox pattern; only enable it when a due date is set.
- [x] 3.3 Include `_countdown` in `initiallyExpanded` so the Advanced tile opens when editing a countdown task.
- [x] 3.4 Pass `countdown: _countdown` into the single-task `Task(...)` construction on save.
- [x] 3.5 Pass `countdown: _countdown` into the recurring first-task and multi-day `Task(...)` construction sites.

## 4. Chip row in the task list

- [x] 4.1 In `lib/task_list/task_list.dart`, subscribe to `TaskService.streamCountdowns` for the current user (alongside the existing day stream).
- [x] 4.2 Compute days-until for each entry as `dueDate - selectedDate` in whole days using `DateService`; keep only entries with a value `> 0`; sort ascending by due date.
- [x] 4.3 Build a `CountdownChipsRow` widget: a `Wrap` of chips, each showing title + "Nd", colored with `Theme.of(context).colorScheme.primary`; render nothing when the list is empty.
- [x] 4.4 Insert `CountdownChipsRow` in the `ReorderableListView` header directly above the `DailyProgress` widget (skip in backlog view).

## 5. Verification

- [x] 5.1 Run `flutter analyze` on the touched files and resolve any issues.
- [ ] 5.2 Manually verify: enabling countdown on a future-dated task shows a chip above the points; the count matches days from the viewed day; the chip disappears on/after the due date.
- [ ] 5.3 Manually verify index consistency: completing, deleting, or disabling countdown removes the chip; changing the due date updates the count.
- [ ] 5.4 Manually verify multiple chips share one row and wrap only on overflow.
