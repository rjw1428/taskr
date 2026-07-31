## Why

Some tasks are genuinely multi-step ("Plan Q3 offsite", "Ship landing page") and today the only options are cramming everything into one task or spinning up a Goal. Goals are the wrong tool — they're auto-generated, AI-driven, long-horizon. What's missing is a lightweight, **manual** breakdown of a single task into steps that can each be scheduled and completed on their own, while the parent stays alive as a container. This is especially valuable in the backlog, where a big item can sit and shed individual steps onto the calendar over time.

## What Changes

- A task can have **child tasks** ("subtasks"), one level deep (subtasks cannot themselves have subtasks). A subtask **is a regular task** with a parent link, so it reuses all existing task behavior (schedule, push, complete, priority, tags, reminders, drag).
- Adding the **first** subtask converts a task into a **backlog-only container**: a parent that has children no longer appears as a row on any day's to-do list — it lives only in the backlog. To keep the work visible, that first child **inherits the parent's date**.
- On a day's **to-do list**, a scheduled subtask appears as an ordinary task row that also displays its **parent's title** (e.g. "Book venue · Plan Q3 offsite").
- In the **backlog**, a parent is shown with its children nested beneath it — including children already scheduled to a date, shown with a **date chip**. There is a single record per subtask; the backlog and the day view are two reads of the same task (no duplication, no sync).
- **Cascade scheduling**: assigning a date to a parent moves only its **unassigned** children to that date; children that were hand-dated keep their date, and **completed** children never move.
- **Carry the remainder** falls out for free: pushing a child moves just that child; completed siblings stay put.
- **Auto-complete**: when the last incomplete child is completed, the parent is automatically marked complete. Adding a new child to a completed parent reopens it.
- Subtasks can be created from a parent in both the backlog and the to-do list, edited, rescheduled, and deleted.

## Capabilities

### New Capabilities
- `task-subtasks`: The parent/child task relationship — data model (`parentId`, denormalized `parentTitle`, child counters), creating/converting a task into a parent, the one-level constraint, delete behavior, and the auto-complete / reopen roll-up between a parent and its children.
- `subtask-scheduling`: How subtasks are scheduled and displayed — child inherits parent date on first add, scheduling/pushing a child, cascade-assigning a parent's unassigned children, completed children not moving, the backlog nested view (with date chips) and the to-do-list row (with parent title breadcrumb).

### Modified Capabilities
<!-- No existing OpenSpec specs define task behavior at requirement level; nothing to modify. -->

## Impact

- **Data model** (`lib/services/models.dart`): `Task` gains `parentId`, `parentTitle` (denormalized for day-view display), and child counters (`childCount`, `childCompletedCount`) for auto-complete without reading every sibling. The vestigial unused `List<String> subtasks` field is removed/replaced. Regenerate `models.g.dart`.
- **Storage**: subtasks are literal tasks in the existing date-partitioned collections (`todos/{uid}/tasks/{date}/items/{id}`), so unscheduled subtasks sit in the `unassigned` (backlog) partition alongside their parent, and scheduled ones sit in their date's partition. To render a parent's scheduled children in the backlog, add a **`userId` field to task docs** and a **`collectionGroup(items)` query** (`where userId == me and parentId == P`) — requires one composite index and one Firestore security rule for the collection-group read.
- **Service** (`lib/services/task.service.dart`): new operations — add/convert subtask, cascade-assign parent, auto-complete/reopen parent (transaction updating the toggled child + the parent's counters), and the backlog child-gathering query. Existing `pushTask`, `deleteTask`, scheduling, and `taskOrder` handling are reused.
- **UI** (`lib/task_list/`): backlog list renders parents with nested children + date chips; the day list renders scheduled subtasks as task rows with a parent-title breadcrumb and hides parents-with-children; the add/edit task form gains "add subtask" affordances.
- **Non-goals / compatibility**: no AI or generation (that's Goals). No nesting beyond one level. No change to Goals, People, Performance, or the redesign work. Existing tasks without children behave exactly as today.
- **Sequencing**: builds on the current data model; best landed **after** `redesign-ui` so the new backlog/day rows are styled in the new design system from the start.
