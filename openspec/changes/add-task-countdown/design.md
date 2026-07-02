## Context

The task list (`lib/task_list/task_list.dart`) is a **single-day view**: it streams only the tasks whose due date equals the currently selected day, via `TaskService.streamTasks(userId, date, tags)`. Tasks are stored per-day at `todos/{uid}/tasks/{date}/items/{taskId}`, and each day document also holds a `taskOrder` array. The day's points are rendered by the `DailyProgress` widget (`lib/shared/progress_bar.dart`) inside the `ReorderableListView` header.

The countdown feature must show, at the top of *any* day view, a set of chips counting down to future-dated tasks. Because the store is partitioned per day and the view only loads one day, the countdown data cannot come from the day's task stream — it must be sourced across days.

Advanced task options (recurring, multi-day, reminders) live in an `ExpansionTile` titled "Advanced" in `lib/task_list/add_task.dart`, each following a `bool` state + toggle + read-on-save pattern.

## Goals / Non-Goals

**Goals:**
- Add a per-task `countdown` flag, toggled in the Advanced section.
- Render a wrapping row of countdown chips above the day's points, visible on every day.
- Each chip shows days from the **viewed day** to the task's **due date**, and disappears at ≤ 0 days.
- Match the app's purple accent (`colorScheme.primary`).
- Avoid expensive cross-day reads and avoid migrating existing task documents.

**Non-Goals:**
- No separate "countdown target" date — the countdown always targets the task's existing `dueDate`.
- No "Today"/overdue chip state — chips simply vanish at zero.
- No countdown for tasks without a due date, and none in the backlog view.
- No extension of any date, no notifications tied to the countdown.

## Decisions

### Decision 1: Target the task's existing `dueDate` (not a new date field)
Per product direction, "days until" is measured to the task's `dueDate`. No new date field is added to `Task`; the toggle is a single boolean. This keeps the model minimal and avoids a second date picker in the form.
- **Alternative considered:** a dedicated `countdownDate`. Rejected — more UI, more state, and the due date already models "when this is for."

### Decision 2: Count from the *viewed* day, disappear at ≤ 0
Days shown = `dueDate - selectedDate` in whole days. When you page the day view forward, counts shrink. A chip renders only when this value is `> 0`; on/after the due date it is omitted. This makes the header consistent with the day being inspected and naturally removes stale chips.

### Decision 3: A per-user `countdowns` index collection (the key architectural choice)
The day view cannot see other days' tasks. Rather than query across days, `TaskService` maintains a small denormalized index:

```
todos/{uid}/countdowns/{taskId}  →  { title: string, dueDate: "YYYY-MM-DD" }
```

- On task **create/update**: if `countdown == true` and a `dueDate` exists, upsert the index doc; otherwise delete any existing index doc for that task id.
- On task **complete** or **delete**: delete the index doc.
- The task list header subscribes to `todos/{uid}/countdowns` (a small collection), filters `dueDate > selectedDate`, sorts by `dueDate` ascending, computes days-until, and renders chips.

**Alternatives considered:**
- **`collectionGroup('items')` query** with `where('countdown', ==, true)`: collection-group queries span all users, so it would require adding a `userId` field to every task doc (a migration) plus a composite index, and still read across many day partitions. Rejected.
- **Reading a window of upcoming day documents** (e.g. next 90 days) and filtering: unbounded, many reads, and misses countdowns beyond the window. Rejected.
- The index collection is tiny (one doc per active countdown), scoped to the user by path, cheap to stream, and requires no change to existing task documents.

### Decision 4: Chip styling via `Theme.of(context).colorScheme.primary`
The task-list add button is a `FloatingActionButton` with no `backgroundColor` override, so it inherits the theme's default primary purple (`#BB86FC` in this dark theme). Chips reference `colorScheme.primary` so they stay in sync if the theme changes, rather than hardcoding the hex.

### Decision 5: Chip row placement and wrapping
Insert a `Wrap` of chips in the `ReorderableListView` header, immediately above the `DailyProgress` widget in `task_list.dart`. `Wrap` keeps chips on one line and flows to additional lines only on overflow, matching the requested behavior. The row is omitted entirely when there are no active countdowns (no empty gap).

## Risks / Trade-offs

- **Index drift** (index doc out of sync with the task) → All countdown mutations funnel through `TaskService` write paths (add/update/complete/delete), and the reader tolerates orphans by filtering on `dueDate > selectedDate`; a stale/orphaned entry at worst shows one extra chip until its date passes. Keep the index writes adjacent to the task writes so they are easy to audit.
- **Task completed/deleted outside the known service paths** → leaves an orphan index doc. Mitigation: the reader treats the index as advisory (title + date only); orphans self-expire when their `dueDate` passes. A future cleanup pass can prune them if needed.
- **Multi-day / recurring tasks** create multiple `Task` docs; enabling countdown on them would index each instance. Mitigation: index keyed by `taskId`, so each instance is independent; acceptable for v1. Documented as a known limitation.
- **Timezone/day math** → compute day difference from date-only strings (`YYYY-MM-DD`) using the existing `DateService`, not raw `DateTime.difference`, to avoid off-by-one from time-of-day.

## Migration Plan

- Additive only: `countdown` defaults to `false`; existing tasks deserialize unchanged (no `models.g.dart` breakage since the field is nullable/defaulted).
- No backfill required — the `countdowns` index populates lazily as users enable the toggle.
- Rollback: hide the toggle and the chip row; the index collection can be left in place harmlessly or deleted.

## Open Questions

- Should completing a countdown task before its due date remove the chip immediately? (Assumed **yes** — completion deletes the index doc.)
- Do we want a max chip count / "+N more" affordance for users with many countdowns? Deferred; `Wrap` handles overflow by wrapping for now.
