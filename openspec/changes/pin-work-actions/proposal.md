# Pin Work Actions

## Why

On the Work page, next actions live inside their priority's card, so the handful of actions the user actually intends to do today are scattered across different cards and get equal visual weight with everything else. Pinning lets the user elevate specific next actions from any priority into one high-visibility list at the top of the Work page.

## What Changes

- Next actions gain a pinned state: any open next action on any work priority can be pinned or unpinned from its row.
- A new pinned-actions section renders at the top of the Work page, above the priority list, showing every pinned open action across all priorities.
- Pinned action cards use a distinct accent color (both in the pinned section and on the source priority's card) to signal "this is a priority action".
- Checking a pinned action in the pinned list completes it exactly like checking it on its source priority card: `completedAt` is set on the action inside its work item and the row disappears from both places (the pinned list shows only open actions, so completion removes it from the pins).
- Completing a pinned action from its source card likewise removes it from the pinned list; Undo restores the action to both lists.
- The pinned section shows which priority each action belongs to, and is hidden entirely when nothing is pinned.
- Pin state is persisted on the next action map in Firestore (`todos/{userId}/work`), so pins sync across devices like everything else on the board.

## Capabilities

### New Capabilities

- `work-pinned-actions`: Pinning and unpinning next actions, the pinned list at the top of the Work page, its distinct card color, cross-list completion behavior, and automatic unpin on completion.

### Modified Capabilities

- `work-board`: The next action data model gains an optional `pinnedAt` field (nullable epoch millis), and card rendering distinguishes pinned open actions with the pinned accent color. (Note: `work-board` currently exists as a delta spec in the `add-work-page` change rather than in `openspec/specs/`; this change layers a further delta on it.)

## Impact

- **Data model**: `NextAction` in `lib/services/models.dart` (+ generated `models.g.dart`) gains `pinnedAt`; existing documents without the field must load with `pinnedAt` null.
- **Service**: pin/unpin is a next-action mutation through the existing `setNextActions` path; complete/undo paths are unchanged (pin state is retained on the action, and visibility in the pinned list is derived from open + pinned).
- **UI**: `lib/work/work_page.dart` (pinned section at top), `lib/work/work_item_card.dart` and `lib/work/next_action_row.dart` (pin toggle, pinned styling), design tokens in `lib/shared/design/tokens.dart` for the pinned accent color.
- **No impact** on tasks, performance, accomplishments, or security rules (same `todos/{userId}/work` documents and access model); no Firestore index or rules changes, so nothing for the user to deploy.
- **Tests**: work service and work page widget tests extend the existing TestEnv harness.
