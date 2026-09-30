## 1. Models and pure logic

- [x] 1.1 Add `WorkItem`, `NextAction`, and `WorkUpdate` models to `lib/services/models.dart` per design D2 (`explicitToJson: true`, list and string defaults for missing fields, `id` excluded from JSON) and regenerate `models.g.dart` with build_runner
- [x] 1.2 Add `test/work_models_test.dart` covering round-trip serialization, defaults when `notes`/`updates`/`nextActions` are absent, and that `id` is not emitted
- [x] 1.3 Create `lib/work/work_logic.dart` with pure helpers: `sendNextActionToEnd`, `completeNextAction`/`undoComplete`, `appendUpdate`, `buildTimeline(WorkItem)` returning typed events sorted oldest first, and `openActions(WorkItem)`
- [x] 1.4 Add `test/work_logic_test.dart` for every helper in 1.3, including timeline ordering with archive and restore events and stability of next-action ids across edits
- [x] 1.5 Create `lib/shared/link_parser.dart` with the pure URL tokenizer (http, https, bare `www.`, trailing punctuation trimmed) and `test/link_parser_test.dart` covering the four scenarios in the work-links spec

## 2. Service layer

- [x] 2.1 Create `lib/services/work.service.dart` using `FirebaseRefs` with `@visibleForTesting` `db`/`auth` setters: `streamActive()` ordered by `position`, `streamArchived()` ordered by `archivedAt` descending, `add`, `update` (title/notes only), `delete`, `setNextActions`, `addUpdate`, `reorder(orderedIds)` as a position-only `WriteBatch`, `archive(id)` and `restore(id)` as atomic move batches, `deleteArchived(id)`
- [x] 2.2 Add `test/work_service_test.dart` with `TestEnv`: create appends with correct `position`, reorder rewrites only `position`, archive/restore move between `work` and `workArchive` atomically with timestamps, restore appends to bottom, delete paths
- [x] 2.3 Add an isolation test in `test/work_service_test.dart` that runs a full lifecycle (create, complete, undo, add update, archive, restore, delete) and asserts the performance, accomplishments, and tasks collections are unchanged, plus a static check that `work.service.dart` imports neither `performance.service.dart` nor `accomplishment.service.dart`

## 3. Links and export

- [x] 3.1 Add `url_launcher` to `pubspec.yaml`, run `flutter pub get`, and add the Android `<queries>` entry for `https` intents in `android/app/src/main/AndroidManifest.xml`
- [x] 3.2 Create `lib/shared/link_text.dart`: a `LinkText` widget rendering tokenizer output as `RichText` with accent-colored underlined tap spans, an injectable launcher callback defaulting to `launchUrl(..., mode: externalApplication)`, and a snackbar on launch failure
- [x] 3.3 Add `test/link_text_test.dart`: plain text renders unchanged, link spans are tappable and invoke the injected launcher with the right URL, launch failure shows a snackbar
- [x] 3.4 Create `lib/work/work_export.dart` with pure `WorkExport.item(WorkItem, {archived})` and `WorkExport.board(active, archived, now)` matching the work-export spec exactly
- [x] 3.5 Add `test/work_export_test.dart` with golden strings for full item, minimal item, archived item, board with both sections, and board with no archived items

## 4. Work page UI

- [x] 4.1 Create `lib/work/work_item_form.dart`: bottom-sheet form for title (required), notes, and optional first next action on create; reused for edit with pre-filled values
- [x] 4.2 Create `lib/work/next_action_form.dart` (text required, optional "waiting on") and `lib/work/work_update_form.dart` (single multiline text, required)
- [x] 4.3 Create `lib/work/work_item_card.dart`: title via `LinkText`, two-line notes preview, "No next action" badge, open next-action rows (checkbox or hourglass for waiting, "Waiting on X" line, send-to-end button, overflow for completing waiting actions), inline add-next-action row, detail chevron, `ReorderableDragStartListener` handle, and overflow menu with Edit, Add update, Send to bottom, Archive, Delete (confirm)
- [x] 4.4 Create `lib/work/work_page.dart`: streams active items, `ReorderableListView` with `buildDefaultDragHandles: false`, optimistic reorder using `TaskListLogic.reorder` then `WorkService.reorder`, complete-with-undo snackbar, empty state, and app-bar actions for Archived and "Copy all as Markdown"
- [x] 4.5 Add `test/work_page_test.dart` with `pumpApp` and `settle`: items render in position order, multiple open actions visible, completed hidden, badge shown/hidden, waiting row rendering, no auto-sort, send to end, send to bottom, drag reorder persists position-only, complete then undo restores the action, empty state, copy-all writes clipboard
- [x] 4.6 Add `test/work_forms_test.dart`: title required, empty next action rejected, empty update rejected, create with first next action yields one open action, edit leaves next actions and updates untouched

## 5. Detail, archive, and history UI

- [x] 5.1 Create `lib/work/work_detail_page.dart`: title, notes, open next actions, derived timeline with distinguishable event kinds, "Copy as Markdown", and for archived items a read-mostly mode with Restore and Delete and no completion or reorder controls
- [x] 5.2 Create `lib/work/work_archive_page.dart` listing archived items newest first with an empty state, each opening the detail page
- [x] 5.3 Add `test/work_detail_page_test.dart` (timeline order, archive/restore entries present, copy writes clipboard, archived mode hides completion controls and offers Restore) and `test/work_archive_page_test.dart` (order, empty state, restore appends to board, delete from archive)

## 6. Navigation and quick action

- [x] 6.1 In `lib/routing.dart` add `'/work'` at index 1 with `Icons.corporate_fare` and `WorkPage`, renumber Performance, Goals, Backlog, People to 2 through 5, and add `final requestedRoute = ValueNotifier<String?>(null)`
- [x] 6.2 In `lib/home/home.dart` add the Work FAB case opening `WorkItemForm` in a bottom sheet, shift the remaining cases, update the People comment to index 5, and listen to `requestedRoute` in `initState` to call `_onItemTapped` for known routes then clear it
- [x] 6.3 In `lib/app.dart` add `workShortcutType = 'work'`, register a "Work" `ShortcutItem`, and route it in `_handleShortcut` via `_whenReadyForShortcut` to set `requestedRoute` to `/work`
- [x] 6.4 Update `test/routing_test.dart` and `test/home_test.dart` to assert the new tab order and icon, and assert FAB behavior by tab label rather than index; add cases for `requestedRoute` selecting Work and ignoring unknown routes
- [x] 6.5 Update `test/app_test.dart` for the fourth shortcut item and that the Work shortcut lands on the Work tab

## 7. Verification

- [x] 7.1 Run `flutter analyze` and `flutter test` and fix all failures
- [x] 7.2 Run `flutter test --coverage` and confirm the new `lib/work/`, `lib/shared/link_*`, and `lib/services/work.service.dart` files are at or above the 90% target for hand-written code
- [ ] 7.3 Run the app and manually verify on a device: drag reorder, send to bottom, waiting row styling, undo, archive and restore, pasted Jira and GitHub links open externally, Work quick action from the home screen, and that the List, Backlog, and Performance tabs show no work data
