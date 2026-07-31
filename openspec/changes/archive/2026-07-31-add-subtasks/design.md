## Context

taskr stores tasks in **date-partitioned** collections: `todos/{uid}/tasks/{date}/items/{taskId}`, where `date` is a day string or `"unassigned"` (the backlog). Each date doc carries a `taskOrder` array for ordering. Tasks already link upward to **Goals** via `goalId`; Goals are an auto-generated, AI-driven, long-horizon layer.

Subtasks are a different need: a **manual**, lightweight breakdown of a single task into steps. This design was worked out in an explore session; the key decisions and the alternatives we rejected are recorded here so the rationale isn't lost.

Constraints:
- Reuse the existing task machinery — a subtask should *be* a task, not a parallel entity, so scheduling / pushing / completing / priority / tags / reminders / drag all work with zero reimplementation.
- Stay within the date-partition model; don't require moving to a new storage architecture.
- Avoid duplicated records / bidirectional sync (a class of bug this project has already been bitten by).

## Goals / Non-Goals

**Goals:**
- One level of parent → child tasks, created manually.
- A subtask is a real task everywhere it appears.
- A parent with children is a backlog-only container; its scheduled children appear on their days and are also listed (with date chips) under the parent in the backlog.
- Cascade-schedule a parent's unassigned children; auto-complete the parent when its last child is done.
- Single source of truth per subtask — no duplicate/mirror docs.

**Non-Goals:**
- No AI or generation (that is Goals).
- No nesting beyond one level.
- No changes to Goals, People, Performance, or the redesign.
- No multi-parent / re-parenting flows in v1 (a subtask belongs to exactly one parent).

## Decisions

### D1: A subtask is a literal task with a `parentId` (Model B, storage option ①)
**Decision:** Add `parentId` to `Task`. A subtask is an ordinary task doc living in the normal date partitions (`unassigned` when not yet scheduled, a date partition once scheduled). Also store a denormalized `parentTitle` so a day row can show the parent without a second read.

**Rationale:** The recurring requirement was "subtasks are regular tasks." Making them literal tasks means every current and future task feature applies for free. The alternatives were heavier:
- **Flat subtask collection (option ②):** subtasks in their own collection with a `dueDate` field. Cheap parent queries, but subtasks become a *distinct* entity and every task interaction (push, complete-scoring, drag, reminders) must be re-implemented and kept at parity — more total work and more "subtasks don't behave like tasks" surface.
- **Duplicate + bidirectional sync:** one canonical copy in the backlog, a mirror in the date partition, synced both ways. Rejected: two sources of truth, echo loops, and partial-failure drift — the same failure mode behind the duplicate-entry-on-save and log data-loss bugs fixed earlier.

The edge-case answers (see D4) removed option ②'s main advantage: cascades only touch co-located `unassigned` children, and the parent is never pushed across partitions, so the expensive cross-partition set-operations that would have favored ② don't occur.

### D2: Parent with children is backlog-only; first child inherits the parent's date
**Decision:** A task that has ≥1 child is never rendered as a row on a day's to-do list — only in the backlog. When a task gains its **first** subtask, the new child inherits the (former) parent's `dueDate`, so the work stays visible on that day as a child row.

**Rationale:** Keeps the day view about actionable steps and the backlog about the plan, and prevents a task from appearing to vanish when you break it down. The parent's own `dueDate` becomes meaningful only as a cascade target (see D4).

### D3: Backlog nesting via a single `collectionGroup` read (no duplication)
**Decision:** To show a parent's scheduled children (which live in other date partitions) under the parent in the backlog, run a `collectionGroup('items')` query filtered by `userId` and `parentId`. Add a `userId` field to every task doc to make this query securable and indexable.

**Rationale:** One record per subtask, read from two angles (its day partition and the backlog aggregation). No mirror docs, no sync. Cost is bounded and one-time: a `userId` field, one composite index (`userId`, `parentId`), and one security rule permitting the collection-group read scoped to the owner.

**Alternative considered:** denormalize a child summary array onto the parent — rejected as another drift surface; the collection-group read is authoritative.

### D4: Cascade scheduling and "carry the remainder"
**Decision:**
- Assigning a date to a parent moves **only its `unassigned` children** to that date. Children with their own date are left alone; **completed** children never move.
- Pushing a **child** moves just that child (it's a normal task push); completed siblings stay. "Carry the remainder" is therefore automatic at the child level — there is no special parent-level push, because a parent-with-children never sits on a day to be pushed.

**Rationale:** Matches how the breakdown is used — a parent sheds unscheduled steps onto the calendar, while steps you've deliberately dated or finished are respected. Because unassigned children are co-located in the `unassigned` partition, the cascade is a normal same-partition schedule, not a scatter.

### D5: Auto-complete / reopen via counters in a transaction
**Decision:** The parent stores `childCount` and `childCompletedCount`. Toggling a child's completion runs a **transaction** that updates the child and the parent's `childCompletedCount`; when completed == count the parent is marked complete, and adding a new child to a completed parent reopens it. Firestore transactions are database-wide, so the parent and a child in different partitions update atomically.

**Rationale:** A running counter avoids reading every sibling on each toggle and is the *only* denormalized state to maintain — far less than mirroring whole docs.

## Risks / Trade-offs

- **Counter drift** (`childCount` / `childCompletedCount` diverging from reality if a write partially fails) → do the child-toggle and parent-counter update in one transaction; provide a recompute path (recount children via the collection-group query) if drift is ever detected.
- **`collectionGroup` security** → requires a rule matching `/{path=**}/items/{id}` gated on `resource.data.userId == request.auth.uid`; the `userId` field must be written on every **subtask** write.
- **`userId` coverage (no backfill needed)** → the collection-group backlog read only matches subtasks (`parentId != null`), which are all created after this feature ships and therefore always carry `userId`. Pre-existing tasks (all `parentId == null`) are excluded by the query's `parentId` filter and are read normally elsewhere, so they never need `userId`. No migration is required — just stamp `userId` on subtask writes.
- **The "task becomes a container" transition** could surprise users (a dated task leaves the day when it gains a child) → mitigated by the first child inheriting the date so the work stays on the day; clear visual treatment of the parent-title breadcrumb.
- **Scoring semantics** — since subtasks are real tasks, each completion scores by its own priority; a parent that is only a container should not double-count. Confirm during implementation (likely: parent contributes no score of its own once it has children).
- **Interaction with recurring / multi-day** — v1 disallows making a recurring or multi-day task into a parent (and vice versa) to avoid a combinatorial mess; enforce in the form.

## Migration Plan

1. Add `parentId`, `parentTitle`, `userId`, `childCount`, `childCompletedCount` to `Task`; remove the unused `List<String> subtasks`; regenerate `models.g.dart`.
2. Backfill `userId` on existing task docs (migration script or lazy on next write).
3. Add the Firestore composite index (`userId`, `parentId`) and the `collectionGroup` security rule; deploy rules.
4. Service layer: add/convert subtask, cascade-assign, auto-complete/reopen transaction, backlog child-gathering query.
5. UI: backlog nested rendering (+ date chips), day-view subtask rows (+ parent-title breadcrumb, hide parents-with-children), add-subtask affordances in the form.
6. Guard rails: block parent↔recurring/multi-day combinations.

**Rollback:** additive fields and a new query; no destructive schema change. Reverting the UI hides the feature; the extra fields on task docs are inert.

## Resolved

- **Container-parent scoring:** a parent that has children contributes **no score of its own**; only children score, each by its own priority. Performance stats must not count the parent.
- **`userId` backfill:** not required — see the "no backfill needed" risk note above. Only subtasks are read via the collection group, and they always carry `userId`.
- **Backlog progress indicator:** yes — show a compact `n/m done` on the backlog parent, driven by the child counters.
- **Deleting a parent:** prompt the user — "delete all steps" vs "keep steps as standalone tasks" (codified in the `task-subtasks` spec).

## Open Questions

- None blocking. (The exact placement/format of the `n/m` indicator is a UI-build detail.)
