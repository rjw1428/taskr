## 1. Data Model

- [x] 1.1 Add `type` field to `Task` model in `lib/services/models.dart` with default value `task`, and regenerate `models.g.dart`
- [x] 1.2 Add a helper getter `isDivider` on `Task` (returns `type == 'divider'`)

## 2. Service Layer

- [x] 2.1 Add `addDivider(String label, String? date)` method to `TaskService` that creates a divider document and appends its ID to `taskOrder`
- [x] 2.2 Ensure `deleteTask` and `restoreTask` work for dividers (skip performance stat updates for dividers)

## 3. Divider Widget

- [x] 3.1 Create `lib/task_list/divider_item.dart` — a widget rendering a horizontal rule with optional centered label, a remove (X) button with undo snackbar, plus a `ReorderableDragStartListener` drag handle

## 4. Task List Integration

- [x] 4.1 Update the item loop in `task_list.dart` to check `task.isDivider` and render `DividerItem` instead of `TaskItem` for dividers
- [x] 4.2 Skip dividers in the `displayTask` progress score calculation

## 5. FAB Long-Press

- [x] 5.1 Wrap the task list FAB (index 0) and backlog FAB (index 3) in `home.dart` with `GestureDetector` for `onLongPress`
- [x] 5.2 On long-press: trigger `HapticFeedback.mediumImpact()`, show a dialog prompting for a label, and call `TaskService.addDivider()` on confirm
