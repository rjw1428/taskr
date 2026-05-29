## Context

The task list in Taskr uses a `ReorderableListView` that displays `Task` objects fetched from Firestore. Tasks are ordered by a `taskOrder` array stored at the date-level document. The list currently only supports one item type (`Task`). The FAB button on the home screen opens an `AddTaskScreen` bottom sheet on tap.

## Goals / Non-Goals

**Goals:**
- Allow users to insert labeled horizontal dividers into their task list
- Dividers participate in the same ordering system as tasks
- Long-press on FAB creates a divider with haptic feedback
- Dividers are draggable and removable

**Non-Goals:**
- Collapsible sections (dividers are purely visual separators)
- Divider-based filtering or grouping logic
- Persisting dividers across date changes (dividers are per-date, like tasks)
- Customizing divider appearance (color, thickness, etc.)

## Decisions

### 1. Store dividers as special Task documents with a `type` field

**Choice**: Add a `type` field to the Task model (`task` or `divider`) rather than creating a separate Firestore collection.

**Why**: Dividers must interleave with tasks in the `taskOrder` array. Using the same collection means the existing `streamTasks` and ordering logic works with minimal changes. A separate collection would require merging two streams and maintaining cross-collection ordering.

**Alternative considered**: Separate `dividers` subcollection — rejected because ordering across two collections adds significant complexity with no benefit.

### 2. Reuse Task model with optional fields

**Choice**: Extend the `Task` class with a `type` field (defaulting to `task`). For dividers, only `id`, `type`, `title` (the label), and `added` are populated.

**Why**: The `ReorderableListView` and `taskOrder` system already work with Task IDs. By making dividers a variant of Task, all existing ordering, add, and delete logic applies without modification.

### 3. Long-press gesture via GestureDetector wrapping the FAB

**Choice**: Wrap the FAB in a `GestureDetector` with `onLongPress` that shows a simple dialog for the divider label, then creates the divider.

**Why**: This is the simplest approach — no UI changes to the FAB itself, just an additional gesture. `HapticFeedback.mediumImpact()` provides tactile feedback on supported devices.

### 4. Render dividers as a distinct widget in the list

**Choice**: In `task_list.dart`, check `task.type` in the loop and render either a `TaskItem` or a new `DividerItem` widget.

**Why**: Clean separation of rendering logic. `DividerItem` is a simple widget with the label, a horizontal line, and a remove button.

## Risks / Trade-offs

- **[Backward compatibility]** Existing tasks in Firestore have no `type` field → Mitigation: Default `type` to `task` in the model, so existing documents parse correctly without migration.
- **[Performance scoring]** Dividers should not affect daily progress scores → Mitigation: Skip dividers in the `displayTask` method's score calculations.
- **[Smart ordering]** The `addTask` method has smart ordering logic based on start time and completion status → Mitigation: Dividers always append to end of list (no start time, not completable), so they hit the simplest code path.
