## Context

The app is a Flutter client over Firestore. Every feature follows the same shape: a `@JsonSerializable` model in `lib/services/models.dart`, a service class that reads `FirebaseRefs.firestore` and `FirebaseRefs.auth` with `@visibleForTesting` setters, an optional `ChangeNotifier` provider, and a feature folder of widgets. Per-user data lives under `todos/{userId}/<collection>` (tasks by date, `people`, etc.) and `firestore.rules` already grants the owner full read/write on that subtree.

Bottom navigation is a static `routeConfig` map in `lib/routing.dart` keyed by path with an explicit `index`. `home.dart` switches on `_selectedIndex` to build the floating action button (FAB), so tab positions are load-bearing. Tab changes go through `_onItemTapped`, which pushes the route on `innerNavigatorKey` and updates state; nothing outside `HomeScreen` can select a tab today. Quick actions are registered in `app.dart` and dispatched by `_handleShortcut` through `_whenReadyForShortcut`, which waits for a navigator context.

The task list persists drag order as a `taskOrder` array on the parent date document and renders with `ReorderableListView`, `buildDefaultDragHandles: false`, and explicit drag handles. `TaskListLogic.reorder` encodes the reorder index-shift quirk as a pure function.

Performance is fed only by `PerformanceService` writes made from the task flows. Accomplishments are their own collection with their own form. Nothing aggregates across collections on the client, and no Cloud Function triggers on Firestore writes, so a new collection is invisible to Performance by construction as long as the work flows never call `PerformanceService` or `AccomplishmentService`.

There is no URL-opening dependency in the app today and no link-aware text widget.

## Goals / Non-Goals

**Goals:**
- A Work tab at index 1 rendering a persistent, user-ordered list of active work items, each showing its title and every open next action.
- Next actions are plain or waiting, visually distinct, in insertion order with an explicit send-to-end.
- Every step is kept: completed next actions, dated progress updates, and archive events form a per-item timeline.
- Archive and restore without losing history.
- URLs anywhere in work text become tappable links.
- A Markdown export of one item or the whole board with a stable, documented shape.
- A home-screen quick action to the Work tab.
- Full isolation from tasks, Performance, records, heatmap, and accomplishments, enforced by structure rather than filtering.
- Testable through the existing harness with `fake_cloud_firestore`, with `url_launcher` the only new dependency.

**Non-Goals:**
- Linking work items to tasks, goals, or people records.
- Due dates, a waiting-since field, reminders, or notifications.
- Any AI integration: no generation, summarization, or sending work data to a model. The export is a plain clipboard copy.
- Search, tags, or grouping on the Work page.
- Editing or deleting history entries once written, except deleting the whole item.

## Decisions

### D1. Two per-user collections: `todos/{userId}/work` and `todos/{userId}/workArchive`

Active items live in `work`; archiving moves the document to `workArchive` in one batch (set in archive, delete from active) and restore does the reverse. Both are covered by the existing `match /todos/{userId}/{document=**}` rule.

Why two collections instead of an `archivedAt` filter: the board query is `orderBy('position')`. Adding `where('archivedAt', isNull: true)` on top of that needs a composite index, which would require a manual deploy and would fail hard if missing. Filtering client-side instead would mean every board load reads every archived document forever, which runs against the app's cost-conscious read patterns. Moving the document keeps the board query single-field and cheap, and the archive view only reads when opened.

Alternative considered: storing work items as undated tasks with a flag. Rejected because tasks carry effort, points, scheduling, recurrence, and performance side effects; every task code path would need a guard, and one missed guard leaks into Performance. A separate collection makes isolation a property of the layout.

### D2. Data model: history is embedded, nothing is deleted on completion

```
WorkItem {
  id            String?          // doc id, stripped before write (Person convention)
  title         String
  notes         String           // free text, links allowed, wait timing lives here
  position      int              // 0-based sort key on the active board (D3)
  nextActions   List<NextAction> // open and completed, insertion order
  updates       List<WorkUpdate> // user-added progress notes
  createdAt     int              // epoch ms
  lastUpdated   int
  archivedAt    int?             // set when moved to workArchive, cleared on restore
  restoredAt    int?             // last restore, for the timeline
}

NextAction {
  id            String   // client-generated, stable across edits
  text          String
  waitingOn     String?  // non-null => waiting; doubles as the label
  createdAt     int
  completedAt   int?     // null while open; set on complete, cleared on undo
}

WorkUpdate {
  id            String
  text          String
  createdAt     int
}
```

The card shows only next actions with `completedAt == null`. Completing sets `completedAt`; the snackbar undo clears it. The timeline on the detail page is derived, not stored: it merges `createdAt`, each `NextAction.createdAt` and `completedAt`, each `WorkUpdate.createdAt`, `archivedAt`, and `restoredAt` into one chronological list. Deriving it avoids a second source of truth that could drift from the embedded lists.

Alternative considered: a `history` subcollection per item. Rejected because history is always shown with its parent, a subcollection doubles reads per item and needs a collection-group rule, and the export would need N+1 reads. Firestore's 1 MiB document cap is far beyond any realistic count of short text entries. Stable ids on every entry make a later move to a subcollection mechanical if it is ever needed.

`explicitToJson: true` is required on `WorkItem`, as on `Person`, so nested lists serialize to maps Firestore accepts.

### D3. Board order is a per-item `position`, rewritten in a batch

The Work page streams `work` ordered by `position`. On drag end and on "Send to bottom", `WorkService.reorder(List<String> orderedIds)` writes `position = index` for every active item in one `WriteBatch`, using `update` on `position` only so a concurrent title or next-action edit elsewhere is not clobbered. New items get `position = current count`. Restored items are appended to the bottom. Archiving an item leaves a gap in positions, which is harmless because the query only needs relative order.

Alternative considered: a `workOrder` array on the user document, matching `taskOrder`. Rejected because it needs two streams combined and reconciled on the client for no benefit on a small single-partition list.

### D4. Reorder logic is pure and reused

The Work page calls `TaskListLogic.reorder(ids, oldIndex, newIndex)` rather than reimplementing the `ReorderableListView` index-shift quirk, and passes the result to `WorkService.reorder`. The page applies the new order optimistically via `setState` so the drop does not flicker while Firestore round-trips; the next stream emission is authoritative.

Next actions are not reorderable; they keep insertion order and waiting actions are never auto-sorted.

### D5. Navigation: insert at index 1, renumber, and add a tab-request hook

`routeConfig` gains `'/work': RouteOption(index: 1, label: "Work", page: WorkPage(), icon: Icons.corporate_fare)`; Performance, Goals, Backlog, People become 2, 3, 4, 5. `RouteOption.icon` is typed `IconData`, so a Material glyph sits beside the Font Awesome tabs without shell changes.

In `home.dart`, `_buildFloatingActionButton` gains a `case 1` that opens the work item form in a `showModalBottomSheet` (same shape as the task and accomplishment sheets), the existing cases shift by one, and the People comment is updated to index 5.

For the quick action, `routing.dart` gains a `ValueNotifier<String?> requestedRoute`. `HomeScreen` listens in `initState`, and when a route is set it resolves the index and calls the existing `_onItemTapped`, then clears the notifier. `app.dart` registers a fourth `ShortcutItem` (`type: workShortcutType`, title "Work") and `_handleShortcut` sets `requestedRoute = '/work'` inside `_whenReadyForShortcut`. This keeps tab selection owned by `HomeScreen` and gives tests a plain notifier to drive.

Alternative considered: keying the FAB switch on route path instead of index. Worth doing but it is a refactor of unrelated tabs, so it is noted as follow-up.

### D6. Editing flows

- **Create item:** FAB bottom sheet with title, notes, and optionally a first next action. Saves with `position = count`.
- **Edit item:** tapping the title area opens the same sheet pre-filled. Notes are edited here.
- **Item overflow menu:** every card has a three-dot menu with Edit, Add update, Send to bottom, Archive, and Delete. Delete confirms first and is the only destructive action; Archive moves the item per D1.
- **Add next action:** an inline "add next action" row at the bottom of each card opens a small sheet with text and an optional "waiting on" field.
- **Complete next action:** a checkbox on the row sets `completedAt` and shows a snackbar with Undo. Copy says "Done" with no points or confetti, so it does not resemble task completion.
- **Toggle waiting:** editing the action and clearing or filling "waiting on" flips the state.
- **Add update:** a sheet with a single multiline field appends a `WorkUpdate` stamped now.
- **Detail page:** opened from a card via a chevron or the overflow menu; shows title, notes, open next actions, and the derived timeline (D2). Archived items open the same page in read-mostly mode with a Restore button.
- **Archived view:** an app-bar action on the Work page pushes a list of `workArchive` items, newest archive first, each opening the detail page.

All writes go through `WorkService`, which touches only `work` and `workArchive`. It has no import of `PerformanceService` or `AccomplishmentService`, and a test asserts the performance collection is untouched after a full create, complete, update, archive, restore, and delete cycle.

### D7. Links: a shared `LinkText` widget and `url_launcher`

A `LinkText` widget under `lib/shared/` takes a string, splits it on a URL regex (`https?://` and bare `www.` prefixes), and renders `RichText` with `TapGestureRecognizer` spans styled with the accent color and underline for matches. Tapping calls `launchUrl` with `LaunchMode.externalApplication`. The regex and the split are a pure function in `link_parser.dart` so the tokenizer can be unit-tested without widgets. Title, notes, next-action text, and update text all render through `LinkText`; the forms are plain text fields, so "paste a link and it becomes tappable" needs no special input handling.

`url_launcher` is the one new dependency. Tests inject a launcher callback so nothing opens a browser under `flutter test`.

Alternative considered: `flutter_linkify`. Rejected because it adds a package for roughly forty lines of code and its styling would need to be overridden to match the design tokens anyway.

### D8. Export: Markdown to clipboard, one shape for item and board

`WorkExport.item(WorkItem)` returns Markdown:

```
## {title}
_Created {date}{, archived {date}}_

{notes}

### Next actions
- [ ] {text}  (waiting on {who})
- [x] {text}  (done {date})

### Updates
- {date}: {text}
```

`WorkExport.board(active, archived)` concatenates items under `# Work` and `# Archived` headers with a generated-on line. Both are pure functions over models, unit-tested against golden strings so the shape stays stable. The Work page app bar has a "Copy all as Markdown" action and the detail page has "Copy as Markdown"; both use `Clipboard.setData` and confirm with a snackbar. The shape is documented in the spec so the user can rely on it in their own documents.

Alternative considered: JSON export. Markdown is readable without tooling and pastes cleanly into notes and review documents. JSON can be added later as a second formatter over the same models.

### D9. Visuals

Each work item is a card using the design-system surface and text tokens. Title is the header, notes preview (first two lines) sits beneath when present, then next-action rows. Plain actions show a checkbox and text. Waiting actions show an hourglass glyph in place of the checkbox, muted ink, and "Waiting on {waitingOn}" under the text; they can still be completed via the row's overflow. An item with zero open next actions shows a warning-toned "No next action" badge next to the title. The drag handle is a `ReorderableDragStartListener` on the card's trailing edge, consistent with the task list.

## Risks / Trade-offs

- [Index-based FAB switch breaks silently when tabs shift] → Update every case in the same commit and extend `home_test.dart` to assert the FAB action per tab label, not per index.
- [Archive move is two writes] → Done in a single `WriteBatch`, so it is atomic; a failure leaves the item where it was and the error surfaces through the existing snackbar path.
- [Batch position rewrite races with a concurrent edit] → Reorder writes only `position` via `update`, never the full document. Last writer wins on position alone, acceptable for a single-user list.
- [Embedded history grows the document] → Entries are short text; the 1 MiB cap allows thousands. Stable ids make a subcollection move mechanical if ever needed.
- [Optimistic reorder diverges from the stream if the batch fails] → The next stream emission restores server order.
- [URL regex mismatches odd links] → Tokenizer is pure and unit-tested; trailing punctuation is trimmed from matches. Unmatched text is still shown, just not tappable.
- [Users expect completed next actions to count for something] → Work is outside Performance by design; completion copy is neutral and there is no scoring.
- [Export shape changes break the user's saved documents or habits] → Golden tests lock the format; changes require updating the spec.

## Migration Plan

No migration. Collections are created on first write. No rules, index, or Cloud Functions changes are required, so nothing needs a manual Firebase deploy. `url_launcher` needs the usual platform setup (iOS `LSApplicationQueriesSchemes` for `https` is not needed for `launchUrl` with a full URL; Android needs a `<queries>` entry for `https` intents), which is part of the tasks. Rollback is removing the route and quick action and leaving orphaned `work` and `workArchive` documents, which nothing else reads.

## Open Questions

None. Resolved with the user: tab icon `corporate_fare`; no auto-sort of waiting actions, explicit send-to-end and send-to-bottom instead; wait timing in notes rather than a field; missing-next-action badge; notes field; snackbar undo with full history retained; archive; no reminders; Work quick action; auto-linked URLs; Markdown export to the clipboard; no AI integration of any kind.
