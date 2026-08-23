## 1. Model and shared constants

- [x] 1.1 Add `lastMaterializedDate` (`String?`, yyyy-MM-dd) and `reminderTimeOfDay` (`String?`, local `HH:mm`) to `RecurringTask` in `lib/services/models.dart`, including `copyWith`
- [x] 1.2 Regenerate `models.g.dart` (`dart run build_runner build --delete-conflicting-outputs`) and confirm both fields round-trip through `toJson`/`fromJson`
- [x] 1.3 Define the horizon and window constants in one place: materialization horizon (60 days), reminder enqueue window (30 days), per-pass enqueue cap (10), batch chunk size (400)
- [x] 1.4 Add a pure helper that expands a local `HH:mm` against a given occurrence date into an absolute UTC ISO-8601 string, with no Firestore dependency

## 2. Batched materialization

- [x] 2.1 Extract a pure function that, given a `RecurringTask` and a "today", returns the occurrence dates inside `[seriesStart, today + horizon]` bounded by the template end date, and always includes the first occurrence even when the series starts beyond the horizon
- [x] 2.2 Add a batched materialization method on `TaskService` that writes the template and its in-horizon occurrences in one `WriteBatch`, chunked at 400 operations
- [x] 2.3 Within that method, use the standard ordered insert for the first occurrence's day and `FieldValue.arrayUnion` for all later days, issuing no reads for the latter
- [x] 2.4 Populate `reminderTime` on each occurrence from the template's `reminderTimeOfDay` inside the same batch, using the helper from 1.4
- [x] 2.5 Apply every series-derived field (`countdown`, `tags`, `priority`, `startTime`, `endTime`, `description`) uniformly to all occurrences, closing the gap where `_addRemainingTasks` dropped them
- [x] 2.6 Set `lastMaterializedDate` on the template as part of the same commit
- [x] 2.7 Wrap the commit in `ackWrite` so a stalled connection yields a queued-write notice instead of an open dialog

## 3. Rolling top-up

- [x] 3.1 Add a collection-group query for a template's occurrences on `(userId, recurringTemplateId)`, catching `failed-precondition` and returning empty, mirroring `HabitService._habitInstanceQuery`
- [x] 3.2 Implement `ensureRecurringInstances(template)`: advance from the watermark to `today + horizon`, dedupe against 3.1 as the authority, write via the batched path, and advance `lastMaterializedDate`
- [x] 3.3 Add an in-memory re-entry guard keyed by template id, mirroring `HabitService._materializing`
- [x] 3.4 Add a pass that streams the user's active templates and tops up each one
- [x] 3.5 Trigger that pass once per launch from the root `userStream` in `lib/main.dart` when auth resolves
- [x] 3.6 Verify the pass is a no-op for series past their end date and for series already materialized to the horizon

## 4. Recurring reminders

- [x] 4.1 Add a time-only reminder control to `lib/task_list/recurring_task_form.dart` writing `reminderTimeOfDay` onto the template
- [x] 4.2 In `lib/task_list/add_task.dart`, present the time-only control when recurrence is enabled and the existing date-and-time picker otherwise, making it unambiguous which reminder is being edited
- [x] 4.3 Extend the top-up pass to enqueue occurrences due within 30 days that have a `reminderTime` and no `reminderTaskName`, via the existing `scheduleReminder` callable, writing the returned name back
- [x] 4.4 Cap enqueue work at 10 per pass and confirm remaining work converges on subsequent passes
- [x] 4.5 Show a `showNoticeSnack` notice at creation when a new series has more in-window reminders than one pass can enqueue; keep the launch-time pass silent with `debugPrint` only
- [x] 4.6 Enqueue inline at creation for the first occurrence only when its reminder falls due before the next pass would run
- [x] 4.7 Confirm occurrences beyond 30 days are skipped without losing their `reminderTime`
- [x] 4.8 Update `pushTask` to re-derive `reminderTime` against the new date when the task's series template defines a `reminderTimeOfDay`, cancelling the prior delivery first
- [x] 4.9 Confirm `pushTask` keeps the existing clear-the-reminder behavior for one-off tasks, series with no reminder time, and occurrences whose template no longer exists

## 5. Rewire creation, edit, and delete

- [x] 5.1 Replace the recurring branch of `_saveTask` in `lib/task_list/add_task.dart` with the batched call, and delete `_addRemainingTasks`
- [x] 5.2 Move `saveRecurringTask` onto the batched path and remove its unguarded raw `.add()`
- [x] 5.3 Rewrite `_deleteRecurringInstances` to use the collection-group query, retaining the per-date scan as the degraded fallback
- [x] 5.4 Cancel enqueued reminders for occurrences being removed on delete-series, preserving completed occurrences as history
- [x] 5.5 Rewrite `updateRecurringTemplate` onto the batched horizon path — cancel future reminders, remove outstanding future occurrences, reset `lastMaterializedDate`, re-materialize — resolving the creation/edit horizon disagreement
- [x] 5.6 Remove the now-unused `_generateRecurringTaskInstances` and reconcile `_generateAllRecurringInstances` with the shared generator
- [x] 5.7 Confirm `lib/task_list/view_series.dart` edit and delete flows work against the rewritten methods

## 6. Tests

- [x] 6.1 Unit-test the horizon expansion helper (2.1): series shorter than the horizon, longer than the horizon, starting beyond the horizon, and bounded by an end date
- [x] 6.2 Unit-test the reminder expansion helper (1.4), including occurrences on both sides of a DST transition
- [x] 6.3 Test batched materialization against `fake_cloud_firestore` via the `late`-field db injection: one commit, correct occurrence count, uniform fields, `taskOrder` populated per day
- [x] 6.4 Test top-up idempotency: a series with no watermark produces no duplicates; two consecutive passes leave the second writing nothing
- [x] 6.5 Test graceful degradation when the collection-group query fails with `failed-precondition`
- [x] 6.6 Test the enqueue window and per-pass cap: nothing beyond 30 days, at most 10 per pass, already-named occurrences skipped, interrupted passes resumed
- [x] 6.7 Test the deferral notice: shown when a created series exceeds the cap, absent when it does not, and absent for launch-time deferral
- [x] 6.8 Test `pushTask` reminder re-derivation across all five cases in the spec, including the deleted-template fallback
- [x] 6.9 Test delete-series: reminders cancelled, completed occurrences preserved, no per-date query storm
- [x] 6.10 Test edit re-materialization across a cadence change and a reminder-time change

## 7. Firebase artifacts (user-deployed)

- [x] 7.1 Add the composite index to `firebase/firestore.indexes.json`: collection group `items`, `COLLECTION_GROUP` scope, `(userId ASC, recurringTemplateId ASC)`
- [x] 7.2 Hand off the exact deploy command (`firebase deploy --only firestore:indexes`) and confirm the client degrades gracefully until it is deployed
- [x] 7.3 Optional: give `scheduleReminder` in `firebase/functions/src/index.ts` a deterministic Cloud Task name (`reminder-{uid}-{taskId}`), catching `ALREADY_EXISTS` (code 6) as success, mirroring `scheduleParkingPrompt`

## 8. Verification

- [ ] 8.1 Create a task recurring every 3 weeks for a year and confirm the form closes immediately with the full horizon materialized
- [ ] 8.2 Create a daily year-long series and confirm only the horizon is written, then confirm a later launch extends it
- [ ] 8.3 Confirm a series created before this change tops up without duplicating occurrences
- [ ] 8.4 Confirm a recurring reminder fires at the configured local time on an occurrence's own date
- [ ] 8.5 Confirm saving offline shows the queued-write notice and closes the form rather than hanging
