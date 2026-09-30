## Why

The task list is built for dated, scored, day-to-day to-dos, and Performance measures how well those get done. There is no place to keep the handful of larger, ongoing priorities visible with a clearly defined next action for each, so they drift out of sight between the daily items. A dedicated Work page keeps priorities in view, makes "what is the next concrete step" answerable at a glance (including when the step is waiting on someone else), and accumulates a durable record of every step taken so the user can look back over a project when writing quarterly reviews, planning, or recalling past decisions.

## What Changes

- Add a new "Work" tab to the bottom navigation, positioned between List and Performance (index 1) with the `corporate_fare` icon. Performance, Goals, Backlog, and People shift right by one.
- Add a Work page listing the user's active work items in a user-controlled order. Items are reordered by drag and drop, and each item's overflow menu offers "Send to bottom". Order persists across sessions and devices.
- Each work item has a title, an optional notes field, and one or more next actions. Every open next action is visible on the item in the list, not hidden behind a detail view. An item with no open next action shows a visible badge so the gap is obvious.
- A next action can be marked as "waiting on" someone or something. Waiting next actions are visually distinguished from actions the user can take. Next actions keep insertion order and are not reorderable. Timing details for a wait live in the item notes, not in a dedicated field.
- Completing a next action removes it from the visible list with a snackbar undo, but it is never deleted: it stays in the item's history with its completion time.
- Each work item keeps its full history: creation, every completed next action, dated progress updates the user adds, and archive events. A detail view shows this as a timeline so the whole project can be reviewed.
- Work items can be archived. Archived items leave the board, remain readable in an Archived view with their full history, and can be restored.
- URLs typed or pasted anywhere in a work item (title, notes, next actions, progress updates) render as tappable links, so Jira tickets and GitHub pull requests are one tap away.
- Export: the Work page and each item can be copied to the clipboard as Markdown, including archived items and full history, in a stable shape suitable for pasting into reviews, planning documents, or notes.
- Add a "Work" home-screen quick action that opens the app on the Work tab.
- Create, edit, and delete work items and next actions. The Work tab's floating action button creates a new work item, consistent with the other tabs.
- Work items are stored separately from tasks. They never appear in List or Backlog, are never scheduled or dated like tasks, and carry no effort or points.
- Work items are excluded from Performance: nothing in the work flows touches performance history, scores, records, or the heatmap, and nothing creates accomplishments.

Out of scope: linking a work item to a task, goal, or person; due dates; reminders or notifications for waiting items; any AI integration (no generation, summarization, or sending work data to a model); search, tags, or grouping. The data model should not preclude these later.

**BREAKING**: none. Existing tabs keep their labels and screens; only their positions after List shift.

## Capabilities

### New Capabilities
- `work-board`: The Work tab and its active list. Work items with title, notes, and next actions; waiting next actions; the missing-next-action badge; drag-and-drop ordering plus send-to-bottom and send-to-end; create, edit, complete-with-undo, and delete flows; the per-tab create action; the Work quick action; and the guarantee that work data stays isolated from the task list, Performance, and accomplishments.
- `work-history`: The per-item record of everything that happened: creation, completed next actions with timestamps, user-added dated progress updates, and archive/restore events, shown as a timeline on the item detail view. Also covers archiving and restoring items and the Archived view.
- `work-links`: Automatic detection and rendering of URLs in work item text as tappable links that open in the system browser.
- `work-export`: Copying a single work item or the whole board (active and archived) to the clipboard as Markdown in a stable, documented shape.

### Modified Capabilities
- `app-navigation-shell`: The preserved-destination requirement currently fixes the order as Today, Performance, Goals, Backlog, People. It changes to List, Work, Performance, Goals, Backlog, People, and the per-tab action button scenario gains the Work tab's add-work-item action.

## Impact

- **Code modified:**
  - `lib/routing.dart` — insert the Work route at index 1, renumber the routes after it, and expose a way for the app shell to request a tab by route (for the quick action).
  - `lib/home/home.dart` — the per-index floating action button and index-based logic (the People comment references index 4) must account for the shifted indices; listen for tab requests.
  - `lib/app.dart` — register the "Work" quick action and route it to the Work tab.
  - `openspec/specs/app-navigation-shell/spec.md` — delta spec for the new tab order and create action.
- **Code added:**
  - A new `lib/work/` feature folder: Work page, work item card, item form, next-action form, progress-update form, item detail (timeline) page, archived list, and Markdown export.
  - A shared link-aware text widget under `lib/shared/`.
  - Work item and next action models in `lib/services/models.dart` (with regenerated `models.g.dart`), a work service and provider under `lib/services/`.
- **Dependencies:** `url_launcher` is added to open links. No other new packages; `quick_actions` is already present.
- **Data:** two new per-user Firestore collections, `todos/{userId}/work` (active) and `todos/{userId}/workArchive` (archived), alongside `people`. The existing rules already scope both to the owner, so no rules, index, or Cloud Functions changes are needed and nothing requires a manual Firebase deploy. No changes to task, performance, or accomplishment collections.
- **Tests:** widget tests for the Work page (ordering, waiting state, multiple next actions, badge, undo), detail timeline, archived view, link rendering, and export shape; service tests through the existing TestEnv harness including an assertion that the performance collection is untouched; updates to navigation and quick-action tests that assert tab indices or shortcut types.
