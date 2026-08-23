## Context

Recurring task series are materialized as real `Task` documents, one per occurrence, under date-partitioned collections (`todos/{uid}/tasks/{date}/items`). Creation currently expands `take(30)` occurrences and writes them with sequential `addTask` calls.

Each `addTask` costs roughly four serial round trips: `getTaskOrder` (`tasks/{date}.get()`), `getTasks` (`items.get()`), then an `ackWrite` over the document set, the `taskOrder` set, and the countdown index sync. Occurrence #1 is awaited before the form closes; the rest are fired unawaited from `_addRemainingTasks`.

Two problems follow. First, the pre-pop path is unguarded: `saveRecurringTask` awaits a raw `.add()` with no `ackWrite`, and `getTasksInOrder`'s reads have no timeout either. Firestore write futures pend indefinitely without a server acknowledgement — the exact failure `ackWrite` was written to prevent — so the dialog can sit on its spinner with no error and no progress. Second, the unawaited tail is ~70 serial round trips for a modest series, each fanning out to `streamTasks` subscribers.

Habits already solve this shape. `HabitService.ensureInstances` materializes a rolling 60-day horizon, tracks a `lastMaterializedDate` watermark, dedupes authoritatively via a collection-group query on `(userId, habitId)`, and guards re-entry with an in-memory set. Recurring tasks predate this and never adopted it. `Habit.reminderTime` ("HH:mm") exists on the model but has zero readers anywhere in `lib/` or `firebase/functions/` — the time-of-day reminder concept was modeled and abandoned.

Constraints that shape everything below:

- **Firestore batches cannot read.** A `WriteBatch` is write-only, so any per-document logic that needs current server state is unavailable inside it.
- **Cloud Tasks caps `scheduleTime` at 30 days out.** A 60-day materialization horizon therefore cannot have all its reminders enqueued at materialization time, regardless of cost.
- **The user deploys Firebase artifacts manually.** Anything requiring an index or a functions deploy must degrade gracefully until that deploy happens.
- **No per-user timezone exists.** `COMMUTE_TIMEZONE` in `index.ts` is a hardcoded constant; there is no timezone on any user profile document.

## Goals / Non-Goals

**Goals:**

- The "Add task" form closes after a single batched commit, independent of series length.
- No unguarded Firestore await remains on the form-close path.
- Series write cost is bounded by the horizon, not by series duration.
- Deleting and editing a series stop scaling with series length.
- Recurring reminders fire at a fixed time of day on each occurrence's own date, correct across DST.
- Ship with **no new Cloud Functions, triggers, or cron jobs**.
- Recurring tasks and habits converge on one materialization contract.

**Non-Goals:**

- Server-side series generation (a Firestore trigger or scheduled expander). Considered and rejected below.
- A nightly server-side reminder sweep. Considered and rejected below.
- Virtual (never-materialized) occurrences rendered from templates at read time.
- Wiring `Habit.reminderTime` to this mechanism. Follow-up once the pattern is proven here.
- Guaranteed reminder delivery without the app being opened. Out of reach without server-side scheduling; see Risks.

## Decisions

### 1. Bounded rolling horizon instead of whole-series materialization

Materialize occurrences in `[seriesStart, today + 60d]` and extend later via a top-up pass. `RecurringTask` gains `lastMaterializedDate`, mirroring `Habit`.

60 days matches `HabitService.ensureInstances`'s default. Matching it is the point: one horizon constant, one mental model, and habits become a working reference implementation for anyone reading the recurring code.

*Alternatives considered.* Keeping `take(30)` bounds the cost but arbitrarily — a daily series gets 30 days of coverage and a yearly series gets 30 years. It also silently truncates: a daily series for a year is quietly capped at 30 occurrences with no top-up to recover the rest. Virtual occurrences would eliminate materialization entirely and are the most elegant end state, but they touch list rendering, ordering, completion, reminders, delete-series, and the Algolia index — far beyond this change.

### 2. One `WriteBatch`, and the `taskOrder` compromise

All in-horizon occurrences plus the template commit in a single `WriteBatch`, chunked at 400 operations (below Firestore's 500 cap, leaving headroom for the template and per-occurrence countdown writes).

The obstacle is `taskOrder`. `addTask` calls `TaskOrdering.insertInto`, which needs the target day's current ordering — a read, impossible inside a batch. But the requirement differs sharply by occurrence:

| Occurrence | Target day | Ordering need |
| --- | --- | --- |
| #1 | usually today, populated | Must slot correctly — the user is looking at it |
| #2..N | future, almost always empty | `arrayUnion([id])` is provably identical to `insertInto` on an empty day |

So: occurrence #1 keeps the existing ordered-insert path (2 reads, both now timeout-guarded); #2..N use `FieldValue.arrayUnion`, exactly as `addTask`'s existing backlog branch already does. Cost becomes a constant 2 reads plus 1 commit, regardless of series length.

*Alternatives considered.* Batching everything and accepting append-to-end for occurrence #1 is cheaper but visibly regresses placement on the one day the user can see. Batching everything and re-sorting today in an unawaited follow-up adds a moving part and a window of visibly-wrong order for no gain over just doing the two reads.

*Accepted imprecision.* If a future occurrence lands on a day that already has tasks — a second series on the same cadence, or a manually scheduled future task — that occurrence appends rather than slotting by priority/time. This is a rare, low-stakes divergence on a day the user is not currently viewing, and the next reorder corrects it.

### 3. Reminders ride the top-up pass; no new server component

The reminder mechanism splits into three layers that reconcile independently:

```
TEMPLATE                          OCCURRENCE DOC                 CLOUD TASKS
todos/{uid}/recurring/{id}        .../items/{taskId}             (queue)

reminderTimeOfDay: "08:30"   →    reminderTime: <ISO UTC>   →    enqueued by the
  (local wall time)                reminderTaskName: null         top-up pass,
                                                                  ≤30d out only
     expanded per occurrence          set once enqueued
     inside the SAME WriteBatch       (dedupe + retry marker)
     → zero extra round trips
```

The client expands `reminderTimeOfDay` against **each occurrence's own local date**, producing the absolute-UTC string that `Task.reminderTime` already uses. This is not merely convenient — it is the only formulation that gets DST right, because 08:30 in November and 08:30 in July are different UTC instants and only per-occurrence expansion captures that. It also means no server component ever needs a timezone, which matters because none is stored.

Enqueueing then becomes ordinary reconciliation work for the top-up pass: find occurrences due within 30 days where `reminderTime != null && reminderTaskName == null`, call the **existing** `scheduleReminder` callable, write back the returned name. The null check is simultaneously the dedupe and the retry marker, so a pass that dies halfway simply finishes on the next launch.

Enqueue work is capped at 10 callables per pass. A daily series converges over a few launches rather than firing 30 sequential RPCs at once; because the guard is self-healing, truncation is safe rather than lossy.

Deferral is surfaced to the user via `showNoticeSnack` **at creation time** — the moment they have context for it — when a newly created series has more in-window reminders than one pass can enqueue. The launch-time top-up pass logs deferral with `debugPrint` but shows nothing, because an unexplained snackbar on every app open is noise the user cannot act on. `showNoticeSnack` already routes through the global `scaffoldMessengerKey` with 4-second deduplication, so it works from either context.

*Alternatives considered.* A nightly scheduled sweep is strictly more reliable — it removes the app-open dependency entirely — but it is a new Cloud Function, and the explicit goal is to ship without one. The data model is deliberately identical under both, so the sweep remains a drop-in retrofit if reliability proves insufficient. A Firestore `onDocumentCreated` trigger costs an invocation per occurrence and still hits the 30-day ceiling, so it needs a deferral path anyway — which is the sweep. Enqueueing inline at save time reintroduces exactly the latency this change removes, and cannot reach past 30 days at all.

### 4. Two different windows, deliberately

Materialization runs to 60 days because batched writes are nearly free. Reminder enqueueing stops at 30 because that is the Cloud Tasks ceiling. The gap is harmless: occurrences between day 30 and day 60 already exist as documents carrying `reminderTime`, and a later pass enqueues them once they come into range.

### 5. Collection-group dedupe, with graceful degradation

Dedupe and delete-series both use a collection-group query on `(userId, recurringTemplateId)`, requiring a new composite index that mirrors the existing `habitId` one.

This is what makes the top-up idempotent against series created by the *old* code, which have no watermark — the query is the authority, so a stale or null `lastMaterializedDate` can never produce duplicates. It also collapses `_deleteRecurringInstances` from up to 1000 date-by-date queries into one.

On `failed-precondition` (index not yet deployed) the query returns empty and the code falls back to the watermark alone, precisely as `_habitInstanceQuery` already does. The change is therefore safe to ship before the deploy.

*Alternative considered.* Storing materialized instance refs on the template document avoids the index entirely, but duplicates state the task documents already hold and can drift out of sync.

### 6. Top-up runs once per launch from the root

The pass is triggered from the root `userStream` provider in `main.dart` when auth resolves. Recurring tasks, unlike habits, have no owning screen, and the task list is the hot screen where a `build()` side effect would run far more often than needed. An in-memory re-entry guard mirrors `HabitService._materializing`.

### 7. Always materialize occurrence #1

`ensureInstances` returns early when the window start is past the horizon, so a series starting six months out would materialize nothing — the user saves the form and sees no task at all. Recurring creation always writes at least the first occurrence regardless of horizon, so a save is always visibly confirmed. (Habits have the same gap; fixing it there is out of scope.)

### 8. Edit is delete-and-recreate on the new path

`updateRecurringTemplate` keeps its delete-and-recreate shape but runs on the rewritten primitives: cancel enqueued reminders for future occurrences, delete future incomplete occurrences via the collection-group query, then re-materialize the horizon in one batch with `lastMaterializedDate` reset. This incidentally resolves the existing bug where creation materializes a different horizon than editing (`take(30)` versus one month).

Completed occurrences are preserved as history, matching what `_deleteRecurringInstances` already does.

### 9. Pushing an occurrence re-derives its reminder

`pushTask` currently cancels the reminder and nulls both `reminderTime` and `reminderTaskName`, so a pushed occurrence loses its reminder permanently. For a series carrying a standing `reminderTimeOfDay`, that is wrong: 8:30am is a property of the series, not of the original date, so it should follow the task when it moves.

When the pushed task belongs to a series whose template has a `reminderTimeOfDay`, `pushTask` SHALL cancel the existing delivery, re-derive `reminderTime` against the new date using the helper from Decision 3, and let the normal enqueue path schedule it. Tasks without a series template, or in a series with no reminder time, keep today's drop behavior.

*Cost.* This adds a template read to the push path. It is a single document fetch, only for tasks that carry a `recurringTemplateId`, and only when a reminder is actually present — the common push (a one-off task, or a series occurrence with no reminder) is unaffected.

*Alternative considered.* Leaving the drop in place is free and keeps the push path untouched, but it produces a silently degrading series: every push permanently removes one occurrence's reminder with no way to restore it short of editing the series.

### 10. Horizon constants stay independent per service

`HabitService` and the recurring-task path each keep their own 60-day default rather than sharing one constant.

The two features share a *contract* — watermark, collection-group dedupe, re-entry guard, rolling top-up — and that is what makes them consistent. The specific horizon length is a tuning parameter, and coupling them would mean any future tuning of one silently changes the other. Keeping them independent also holds this change to zero edits in habit code, which matters while the pattern is still being proven on recurring tasks.

*Trade-off accepted.* The alignment at 60 days is now conventional rather than enforced, and could drift. That is the intended latitude.

### 11. Optional: deterministic Cloud Task names

Recommended but not required. `scheduleReminder` currently lets Cloud Tasks generate a name, so two devices running the top-up before either writes `reminderTaskName` produce two Cloud Tasks and two notifications. Naming the task `reminder-{uid}-{taskId}` makes the second attempt collide with `ALREADY_EXISTS` (code 6), caught and treated as success — the pattern `scheduleParkingPrompt` already uses. Roughly three lines in an existing function; the client design does not depend on it.

## Risks / Trade-offs

**Reminders depend on the app being opened at least once every 30 days.** → Not a regression: reminders are already entirely client-scheduled (`add_task.dart` calls `scheduleReminder` inline on save), and nothing schedules them today without the app running. A 30-day window is the maximum reach the platform allows. If this proves insufficient, the nightly sweep is a drop-in addition against an unchanged data model.

**A reminder for a same-day occurrence created today may be missed** if the launch pass already ran. → The creation path enqueues inline for occurrence #1 when its reminder falls inside the current gap — one callable, only in the case where it is actually urgent.

**Multi-device double-enqueue produces duplicate notifications.** → Decision 11. Until deployed, the exposure is narrow: both devices must run the pass for the same occurrence before either writes `reminderTaskName`.

**The collection-group index is not deployed at ship time.** → Graceful degradation to watermark-only dedupe (Decision 5). Delete-series retains the per-date fallback until then.

**Existing series have no watermark and unknown materialization state.** → The collection-group query is the authority, so the first top-up over a legacy series heals it rather than duplicating. Verify explicitly against a series created by the old code.

**Future occurrences appending rather than slotting in `taskOrder`.** → Accepted, scoped in Decision 2.

**Batch partially applied.** → A `WriteBatch` is atomic, so the failure mode is all-or-nothing, and `ackWrite` surfaces it. Multi-chunk series (>400 operations, i.e. a daily series near the horizon) are not atomic *across* chunks; a mid-sequence failure leaves a partially materialized series, which the next top-up pass completes.

**The push path gains a template read.** → Decision 9. Bounded to tasks that carry both a `recurringTemplateId` and a reminder; every other push is unchanged. If the template has been deleted out from under the occurrence, re-derivation is skipped and the old drop behavior applies.

**Horizon constants drift apart between habits and recurring tasks.** → Accepted, scoped in Decision 10.

## Migration Plan

No data migration is required — both new `RecurringTask` fields are nullable and existing series documents remain valid.

1. Ship the client change. It functions with watermark-only dedupe and the existing per-date delete fallback.
2. Deploy the index: `firebase deploy --only firestore:indexes` with collection group `items`, `(userId ASC, recurringTemplateId ASC)`.
3. Optionally deploy the `scheduleReminder` hardening (Decision 9).

Legacy series heal on their first top-up pass. Rollback is a client revert: the new fields are simply ignored by the old code, and occurrences already materialized remain valid task documents.

## Open Questions

- **Is creation-time the right and only place for the deferral notice?** The requirement is a UI notice; the choice to show it at creation and stay silent during the launch pass is a placement call made in Decision 3, not a given. If a launch-time notice is wanted too, it is a one-line change.
- **Should the deleted-template case on push be reported?** Decision 9 silently falls back to dropping the reminder when a series occurrence outlives its template. That is already an inconsistent state the app tolerates elsewhere (`view_series.dart` renders an orphaned-series view for it), so staying quiet is consistent — but it is a choice.
