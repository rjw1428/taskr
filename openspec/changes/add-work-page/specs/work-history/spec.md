## ADDED Requirements

### Requirement: Progress updates
The system SHALL let the user append a dated progress update to a work item via an "Add update" action in the item's overflow menu and on the detail page. Each update SHALL have a stable `id`, non-empty `text`, and `createdAt` set at creation. Updates SHALL NOT be editable or deletable individually.

#### Scenario: Add an update
- **WHEN** the user submits "Shipped phase 1 to staging"
- **THEN** the item's `updates` list SHALL gain an entry with that text and `createdAt` now, and `lastUpdated` SHALL be refreshed

#### Scenario: Empty update rejected
- **WHEN** the user submits an empty update
- **THEN** the sheet SHALL show a validation error and SHALL NOT write

### Requirement: Completed next actions are retained
The system SHALL keep completed next actions in the item's `nextActions` list with their `completedAt` timestamp for as long as the item exists.

#### Scenario: Completed action survives
- **WHEN** a next action is completed and the app is restarted
- **THEN** the action SHALL still be present in the stored item with its `completedAt`

### Requirement: Item detail page with timeline
The system SHALL provide a detail page for a work item showing its title, notes, open next actions, and a chronological timeline derived from the item's data: creation, each next action's creation and completion, each progress update, and each archive and restore event. The timeline SHALL NOT be stored separately.

#### Scenario: Timeline order
- **WHEN** an item was created, then had a next action added and completed, then an update added
- **THEN** the detail page SHALL list those four events oldest first with their timestamps

#### Scenario: Timeline includes archive events
- **WHEN** an item has been archived and later restored
- **THEN** the timeline SHALL include an "Archived" entry and a "Restored" entry at their times

#### Scenario: Timeline distinguishes event kinds
- **WHEN** the timeline is rendered
- **THEN** completed next actions, progress updates, and lifecycle events SHALL be visually distinguishable

#### Scenario: Open detail from card
- **WHEN** the user taps the detail affordance on a card
- **THEN** the detail page for that item SHALL open with an animated transition

### Requirement: Archive a work item
The system SHALL provide an Archive action in the item's overflow menu that moves the document from `todos/{userId}/work` to `todos/{userId}/workArchive` in one atomic batch, setting `archivedAt` and preserving all other fields including next actions and updates.

#### Scenario: Archive moves the document
- **WHEN** the user archives an item
- **THEN** the item SHALL no longer exist in `work`, SHALL exist in `workArchive` with identical content plus `archivedAt` now, and SHALL disappear from the board

#### Scenario: Archive is atomic
- **WHEN** the archive batch fails
- **THEN** the item SHALL remain in `work` unchanged and an error SHALL be surfaced via snackbar

### Requirement: Archived view
The system SHALL provide an Archived view reachable from the Work page app bar, listing archived items newest `archivedAt` first, each opening the detail page in a read-mostly mode with a Restore action.

#### Scenario: Archived list order
- **WHEN** two items were archived on different days
- **THEN** the more recently archived item SHALL appear first

#### Scenario: Archived detail is read-mostly
- **WHEN** the user opens an archived item
- **THEN** the detail page SHALL show its full timeline and notes, SHALL offer Restore and Copy as Markdown, and SHALL NOT offer next-action completion or reorder controls

#### Scenario: Empty archive
- **WHEN** no items are archived
- **THEN** the view SHALL show an empty-state message

### Requirement: Restore an archived item
The system SHALL move an archived item back to `todos/{userId}/work` in one atomic batch, clearing `archivedAt`, setting `restoredAt`, and appending it to the bottom of the board.

#### Scenario: Restore
- **WHEN** the user restores an item while three active items exist
- **THEN** the item SHALL appear on the board in fourth position with `restoredAt` now and its full history intact

### Requirement: Delete from archive
The system SHALL allow permanent deletion of an archived item after confirmation.

#### Scenario: Delete archived
- **WHEN** the user confirms Delete on an archived item
- **THEN** the document SHALL be removed from `workArchive`
