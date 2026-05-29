## Why

The task list currently displays tasks as a flat list with no visual grouping. Users need a way to organize and visually separate tasks into sections (e.g., "Morning", "After Work", "Errands") to better structure their day.

## What Changes

- Add a new "divider" item type that renders as a horizontal rule with a user-provided label
- Dividers are created via long-press on the existing FAB (add task) button, with haptic feedback
- Dividers appear at the end of the list on creation, prompting for a label
- Dividers are draggable to any position in the list (using the existing ReorderableListView)
- Each divider has a remove button to delete it
- Dividers participate in the same ordering system as tasks (taskOrder array in Firestore)

## Capabilities

### New Capabilities
- `task-list-divider`: Labeled horizontal rule dividers in the task list, including creation via long-press, drag reordering, and removal

### Modified Capabilities

None - no existing spec-level behavior changes. The existing task ordering and reorderable list infrastructure is reused but not modified at the requirements level.

## Impact

- `lib/services/models.dart` - New Divider model (or flag on existing Task model)
- `lib/services/task.service.dart` - CRUD operations for dividers, integration with taskOrder
- `lib/task_list/task_list.dart` - Render dividers alongside tasks, handle mixed-type list
- `lib/home/home.dart` - Long-press gesture on FAB with haptic feedback
- Firestore `items` subcollection - stores divider documents alongside tasks
