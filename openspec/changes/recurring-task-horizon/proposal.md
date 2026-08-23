## Why

Saving a recurring task holds the "Add task" form open behind a spinner while it writes the whole series one document at a time. Creating a task that repeats every 3 weeks for a year takes ~70 serial Firestore round trips, and the writes that happen *before* the form closes are not timeout-guarded at all — `saveRecurringTask` awaits a raw `.add()` with no `ackWrite`, so on a cold or flaky connection the dialog can hang indefinitely.

The codebase already solved this shape of problem for habits: materialize a bounded rolling horizon and top it up over time. Recurring tasks predate that pattern and never adopted it. Aligning them removes the hang, bounds the write cost, and makes the two features behave consistently — including reminders, where `Habit.reminderTime` ("HH:mm") exists on the model but was never implemented anywhere.

## What Changes

**Series creation becomes a single batched write**
- Materialize only occurrences within a bounded horizon (60 days) instead of `take(30)` of the whole series.
- Write the template and all in-horizon occurrences in one `WriteBatch` — one commit, zero reads — instead of N sequential `addTask` calls.
- Guard the template write with `ackWrite` so a stalled connection surfaces as a queued-write notice rather than an open dialog.
- Always materialize at least the first occurrence, even when the series starts beyond the horizon, so saving is always visibly confirmed.

**Series gain a rolling top-up**
- `RecurringTask` gains `lastMaterializedDate`, mirroring `Habit`.
- A new top-up pass extends each active series to `today + 60 days`, deduped by watermark plus a collection-group query, with an in-memory re-entry guard — the same contract as `HabitService.ensureInstances`.
- The pass runs once per launch, from the root `userStream` in `main.dart`.

**Recurring reminders (new capability)**
- The recurring form offers a **time-only** reminder ("Remind me at 8:30am") instead of the one-off form's date-and-time picker. The date comes from each occurrence.
- The template stores `reminderTimeOfDay` as local "HH:mm"; materialization expands it per occurrence into the existing `Task.reminderTime` absolute-UTC field, so DST is handled correctly by construction and no server-side timezone is needed.
- The same top-up pass enqueues Cloud Tasks for occurrences due within 30 days (the Cloud Tasks `scheduleTime` ceiling) that have a `reminderTime` and no `reminderTaskName`, using the **existing** `scheduleReminder` callable. Enqueue work is capped per pass and converges across launches; `reminderTaskName == null` serves as both dedupe and retry marker.
- Deleting or editing a series cancels its already-enqueued reminders.
- Pushing an occurrence re-derives its reminder against the new date instead of dropping it, so a standing series reminder follows the task when it moves.
- When a new series has more in-window reminders than one pass can enqueue, the user is told at creation time that scheduling is still in progress.

**Delete and edit stop scaling with series length**
- `_deleteRecurringInstances` currently expands up to 1000 dates and issues one query per date. Replace with a single collection-group query on `(userId, recurringTemplateId)`.
- `updateRecurringTemplate` (today: delete-all, recreate, regenerate a one-month window) is rewritten onto the same batched + horizon path, resolving the existing disagreement where creation and editing use different horizons.

**Consistency fixes**
- `_addRemainingTasks` drops `countdown` and other fields that the first occurrence keeps; batched materialization gives every occurrence identical field treatment.

**Explicitly out of scope**
- No new Cloud Functions, triggers, or cron jobs. The only required server-side change is one Firestore index (configuration, not code). One optional ~3-line hardening of the existing `scheduleReminder` — a deterministic Cloud Task name, mirroring the parking prompt — is recommended for multi-device dedupe but is not needed to ship.
- Wiring `Habit.reminderTime` to this mechanism is a follow-up once the pattern is proven. This change touches no habit code; the 60-day horizon is defaulted independently per service rather than shared, so habits are left entirely alone.
- Reminders remain client-scheduled, as they are today. A series needs the app opened at least once every 30 days to stay covered. This is the existing trust model, not a regression.

## Capabilities

### New Capabilities
- `recurring-task-series`: How a recurring task series is defined, materialized on a bounded rolling horizon, topped up over time, edited, and deleted — including per-occurrence time-of-day reminders and their scheduling lifecycle.

### Modified Capabilities

None. No existing spec in `openspec/specs/` covers recurring tasks; `habits-and-streaks` describes the parallel habit mechanism and is unchanged by this work.

## Impact

**Client code**
- `lib/services/task.service.dart` — `saveRecurringTask`, `_addRecurringTask`, `_generateRecurringTaskInstances`, `_generateAllRecurringInstances`, `_deleteRecurringInstances`, `updateRecurringTemplate`, `deleteRecurringTemplate`; a new batched materialization path alongside `addTask`.
- `lib/services/models.dart` (+ `models.g.dart`) — `RecurringTask` gains `lastMaterializedDate` and `reminderTimeOfDay`.
- `lib/task_list/add_task.dart` — recurring branch of `_saveTask` collapses to the batched call; `_addRemainingTasks` is removed; the reminder row becomes time-only when recurring is on.
- `lib/task_list/recurring_task_form.dart` — owns the time-only reminder control.
- `lib/task_list/view_series.dart` — edit and delete flows follow the rewritten service methods.
- `pushTask` in `lib/services/task.service.dart` — re-derives a series reminder for the new date rather than clearing it.
- `lib/main.dart` — root `userStream` triggers the once-per-launch top-up pass.
- New service surface for the top-up + reminder reconciliation, modeled on `HabitService.ensureInstances`.

**Data**
- New fields on existing `todos/{uid}/recurring/{id}` documents; both nullable, so existing series keep working untouched.
- Existing series created under the old code have no watermark. The collection-group dedupe makes the first top-up pass over them idempotent, so they heal rather than duplicate.

**Server (user-deployed)**
- One new Firestore composite index: collection group `items`, `(userId ASC, recurringTemplateId ASC)`, mirroring the existing `habitId` index. Code must degrade gracefully on `failed-precondition` — falling back to the watermark alone, as `_habitInstanceQuery` already does — so the change is safe to ship before the index is deployed.
- Optional: deterministic Cloud Task naming in `scheduleReminder` (`firebase/functions/src/index.ts`).

**Platform constraints**
- Cloud Tasks caps `scheduleTime` at 30 days out, which is why the reminder enqueue window is narrower than the 60-day materialization horizon.
- Firestore `WriteBatch` caps at 500 operations; materialization chunks accordingly.
