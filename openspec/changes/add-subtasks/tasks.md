# Implementation Tasks: Add Subtasks

## 1. Data Model

- [x] 1.1 Add `parentId` (String?) and `parentTitle` (String?) to `Task` in `models.dart`
- [x] 1.2 Add `userId` (String?) and child counters `childCount` / `childCompletedCount` (int) to `Task`
- [x] 1.3 Remove the unused `List<String> subtasks` field; add a `bool get isSubtask => parentId != null` and `bool get isParent => childCount > 0` helper
- [x] 1.4 Regenerate `models.g.dart` (`build_runner`) and confirm `toDbTask()` serializes the new fields
- [x] 1.5 Ensure every task write (`addTask`, `updateTask`, `pushTask`, restore, multi-day, recurring) stamps `userId`

## 2. Firestore Access (backlog cross-partition read)

- [x] 2.1 Add a Firestore composite index on task items for (`userId`, `parentId`)
- [x] 2.2 Add a security rule allowing an owner's `collectionGroup('items')` read (`resource.data.userId == request.auth.uid`); deploy rules
- [x] 2.3 Add `TaskService.streamSubtasks(userId)` — a `collectionGroup('items')` query `where userId == uid and parentId != null`, grouped by `parentId`
- [x] 2.4 No `userId` backfill needed — verify the collection-group read only matches subtasks (`parentId != null`, always stamped with `userId`); confirm every subtask write sets `userId`

## 3. Subtask Lifecycle (service)

- [x] 3.1 `addSubtask(parent, title, ...)` — create a child task with `parentId`/`parentTitle`; if it's the parent's first child, inherit the parent's `dueDate` and clear the parent's own day placement (becomes a container)
- [x] 3.2 Increment `childCount` on the parent within the same operation
- [x] 3.3 Reopen the parent (set incomplete) when a new incomplete child is added to a completed parent
- [x] 3.4 Auto-complete/reopen transaction: toggling a child's `completed` updates the child and the parent's `childCompletedCount` atomically; set parent complete when completed == count, reopen when it drops below
- [x] 3.5 `deleteParent(parent, {required keepChildren})` — either delete parent + all children, or delete the parent and null out each child's `parentId`/`parentTitle` (orphan to standalone)
- [x] 3.6 Add a `recomputeParentCounters(parentId)` recovery path (recount via `streamSubtasks`) for counter drift
- [x] 3.7 Guard rails: block converting a recurring or multi-day task into a parent (and adding subtasks to one)

## 4. Scheduling & Cascade (service)

- [x] 4.1 Scheduling a child reuses the existing schedule/move path (unassigned → date partition); verify `parentId`/`parentTitle` survive the move
- [x] 4.2 `assignParentDate(parent, date)` — move only the parent's `unassigned`, incomplete children to `date`; leave hand-dated and completed children untouched
- [x] 4.3 Confirm `pushTask` on a subtask moves only that child (carry-the-remainder is automatic); completed siblings unaffected

## 5. Backlog UI

- [x] 5.1 In the backlog list, render each parent as a container with its children nested beneath (combine the `unassigned` partition with `streamSubtasks` grouped by parent)
- [x] 5.2 Show a date chip on children that are scheduled to a date
- [x] 5.3 Add an "add subtask" affordance on a backlog parent
- [x] 5.4 Add "assign date to parent" affordance that triggers the cascade (4.2)
- [x] 5.5 Show an `n/m done` progress indicator on the backlog parent using the child counters

## 6. To-Do List UI

- [x] 6.1 Render a scheduled subtask as a normal task row that also shows the parent title (e.g. "Book venue · Plan Q3 offsite")
- [x] 6.2 Hide parents-with-children from day lists (they are backlog-only)
- [x] 6.3 Add an "add subtask" affordance on a day task; adding the first subtask converts the task to a container and keeps the child on the day (date inheritance)
- [x] 6.4 Wire child completion on the day to the auto-complete transaction (3.4)

## 7. Scoring & Edge Cases

- [x] 7.1 Implement scoring: a container parent contributes no score of its own; each child scores by its own priority; confirm performance stats aren't double-counted
- [x] 7.2 Handle deleting a scheduled child (removes from its day; decrements parent counters)
- [x] 7.3 Handle the delete-parent prompt in the UI (delete steps vs keep steps → calls 3.5)

## 8. Testing & Verification

- [ ] 8.1 Add a subtask to a backlog task; verify it nests under the parent
- [ ] 8.2 Add a subtask to a scheduled day task; verify the parent leaves the day and the child inherits the date
- [ ] 8.3 Schedule a child to a date; verify it shows on that day with parent title and still nests under the parent in the backlog with a date chip
- [ ] 8.4 Assign a date to a parent; verify only unassigned+incomplete children move
- [ ] 8.5 Complete all children; verify the parent auto-completes; un-complete one; verify it reopens
- [ ] 8.6 Add a child to a completed parent; verify it reopens
- [ ] 8.7 Push an incomplete child; verify completed siblings stay
- [ ] 8.8 Delete a parent both ways (delete steps / keep steps)
- [ ] 8.9 Verify no duplicate records exist and both views reflect a single edit
- [ ] 8.10 Verify existing childless tasks behave exactly as before
