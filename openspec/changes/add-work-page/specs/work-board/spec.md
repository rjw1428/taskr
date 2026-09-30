## ADDED Requirements

### Requirement: Work item data model
The system SHALL store work items as documents in `todos/{userId}/work` with fields `title` (non-empty string), `notes` (string, may be empty), `position` (integer sort key), `nextActions` (list of next action maps), `updates` (list of progress update maps), `createdAt` and `lastUpdated` (epoch milliseconds). Each next action SHALL have a client-generated stable `id`, `text`, optional `waitingOn` string, `createdAt`, and nullable `completedAt`. Work items SHALL NOT carry effort, points, dates, tags, or recurrence.

#### Scenario: Creating a work item
- **WHEN** the user saves a new work item with title "Migrate billing service"
- **THEN** the system SHALL write a document under `todos/{userId}/work` with that title, empty notes, empty `updates`, `createdAt` and `lastUpdated` set to now, and `position` equal to the current count of active items

#### Scenario: Document id is not stored as a field
- **WHEN** a work item is written or updated
- **THEN** the payload SHALL NOT contain an `id` field; the document id is the identity

#### Scenario: Missing optional fields on read
- **WHEN** a stored document lacks `notes`, `updates`, or `nextActions`
- **THEN** the model SHALL load with empty string or empty list defaults instead of failing

### Requirement: Work page lists active items in user order
The system SHALL render the Work page as a list of active work items ordered by ascending `position`, updated live from Firestore.

#### Scenario: Items render in position order
- **WHEN** the active collection holds items with positions 2, 0, 1
- **THEN** the Work page SHALL display them in the order of positions 0, 1, 2

#### Scenario: Empty board
- **WHEN** the user has no active work items
- **THEN** the Work page SHALL show an empty-state message inviting them to add a work item, not an error

### Requirement: Drag-and-drop reorder persists
The system SHALL let the user reorder work items by dragging a handle on each card, apply the new order immediately, and persist it by writing `position` for every active item in a single batch.

#### Scenario: Drag to a new position
- **WHEN** the user drags the third item to the first position
- **THEN** the list SHALL show the new order before the write completes
- **AND** a single batch SHALL update `position` on each active item to match the new order

#### Scenario: Reorder writes only position
- **WHEN** a reorder batch is written
- **THEN** each write SHALL update only the `position` field and SHALL NOT overwrite title, notes, next actions, or updates

#### Scenario: Order syncs across devices
- **WHEN** the order is changed on one device
- **THEN** another device streaming the same collection SHALL show the new order without a restart

### Requirement: Send item to bottom
The system SHALL provide a "Send to bottom" action in each work item's overflow menu that moves the item to the last position, persisted the same way as a drag.

#### Scenario: Send to bottom
- **WHEN** the user chooses "Send to bottom" on the first of four items
- **THEN** that item SHALL become the fourth and the other three SHALL shift up, with positions rewritten in one batch

### Requirement: Card shows title, notes preview, and open next actions
The system SHALL render each work item card with its title, a preview of its notes when notes are non-empty, and every next action whose `completedAt` is null, in insertion order.

#### Scenario: Multiple open next actions
- **WHEN** an item has three open next actions
- **THEN** all three SHALL be visible on the card without opening a detail view

#### Scenario: Completed next actions are hidden on the card
- **WHEN** an item has two open and one completed next action
- **THEN** the card SHALL show only the two open actions

#### Scenario: Notes preview
- **WHEN** an item has notes
- **THEN** the card SHALL show the first two lines of the notes beneath the title

### Requirement: Missing next action badge
The system SHALL display a visible "No next action" badge on any work item card that has zero open next actions.

#### Scenario: Badge shown
- **WHEN** an item has no open next actions
- **THEN** the card SHALL show the badge next to the title

#### Scenario: Badge hidden
- **WHEN** an item has at least one open next action
- **THEN** the card SHALL NOT show the badge

### Requirement: Waiting next actions
The system SHALL treat a next action with a non-null `waitingOn` as waiting, render it distinctly from actionable next actions, and show "Waiting on {waitingOn}" beneath its text.

#### Scenario: Waiting action rendering
- **WHEN** a next action has `waitingOn` = "Sam"
- **THEN** the row SHALL show an hourglass glyph in place of the checkbox, muted text styling, and the line "Waiting on Sam"

#### Scenario: Toggle waiting off
- **WHEN** the user edits a waiting next action and clears the "waiting on" field
- **THEN** the next action SHALL render as an actionable row with a checkbox

#### Scenario: No automatic sorting of waiting actions
- **WHEN** an item has a waiting action followed by an actionable action
- **THEN** the card SHALL keep that insertion order and SHALL NOT move the waiting action

### Requirement: Send next action to end
The system SHALL provide a per-row "send to end" control on every open next action that moves it to the last position within its item in a single write.

#### Scenario: Send to end
- **WHEN** the user taps "send to end" on the first of three open next actions
- **THEN** it SHALL become the third and the item's `nextActions` list SHALL be rewritten once

### Requirement: Add next action
The system SHALL provide an inline "add next action" row on each card that opens a sheet with a text field and an optional "waiting on" field, and appends the new next action to the item.

#### Scenario: Add an actionable next action
- **WHEN** the user enters "Draft the RFC" and leaves "waiting on" blank
- **THEN** the item SHALL gain a next action with that text, `waitingOn` null, `createdAt` now, and `completedAt` null

#### Scenario: Add a waiting next action
- **WHEN** the user enters "Get numbers" and "waiting on" = "Finance"
- **THEN** the item SHALL gain a next action with `waitingOn` = "Finance"

#### Scenario: Empty text rejected
- **WHEN** the user submits with empty text
- **THEN** the sheet SHALL show a validation error and SHALL NOT write

### Requirement: Complete next action with undo
The system SHALL mark a next action complete by setting `completedAt`, remove it from the card, and show a snackbar with an Undo action that clears `completedAt`. Completion SHALL NOT delete the next action, award points, or show celebratory feedback.

#### Scenario: Complete
- **WHEN** the user checks a next action
- **THEN** its `completedAt` SHALL be set to now, the card SHALL no longer show it, and a snackbar with "Undo" SHALL appear

#### Scenario: Undo
- **WHEN** the user taps Undo before the snackbar dismisses
- **THEN** `completedAt` SHALL be cleared and the action SHALL reappear in its original position on the card

#### Scenario: Complete a waiting action
- **WHEN** the user completes a waiting next action via the row's overflow
- **THEN** it SHALL be completed exactly like an actionable one

### Requirement: Create and edit work items
The system SHALL provide a form, opened from the Work tab's floating action button for creation and from the card for editing, with fields for title, notes, and on creation an optional first next action.

#### Scenario: Title required
- **WHEN** the user submits the form with an empty title
- **THEN** the form SHALL show a validation error and SHALL NOT write

#### Scenario: Edit updates lastUpdated
- **WHEN** the user edits the notes of an existing item
- **THEN** the item SHALL be updated with the new notes and `lastUpdated` set to now, leaving next actions and updates untouched

#### Scenario: Create with first next action
- **WHEN** the user creates an item and fills the optional first next action
- **THEN** the new item SHALL have exactly one open next action

### Requirement: Delete work item
The system SHALL provide a Delete action in the item's overflow menu that asks for confirmation and then permanently removes the document.

#### Scenario: Confirmed delete
- **WHEN** the user chooses Delete and confirms
- **THEN** the document SHALL be removed from `todos/{userId}/work`

#### Scenario: Cancelled delete
- **WHEN** the user chooses Delete and cancels
- **THEN** nothing SHALL be written

### Requirement: Work quick action
The system SHALL register a "Work" home-screen quick action that opens the app on the Work tab.

#### Scenario: Launch via quick action
- **WHEN** the user triggers the "Work" quick action
- **THEN** the app SHALL open with the Work tab selected once the home screen is ready

#### Scenario: Quick action while already open
- **WHEN** the app is already running on another tab and the quick action fires
- **THEN** the home screen SHALL switch to the Work tab

### Requirement: Isolation from tasks, performance, and accomplishments
The system SHALL keep work data entirely separate from tasks, performance history, records, the heatmap, and accomplishments. The work service SHALL NOT depend on the performance or accomplishment services.

#### Scenario: Work items do not appear in task lists
- **WHEN** work items exist
- **THEN** neither the List tab nor the Backlog tab SHALL show them

#### Scenario: Performance untouched by a full lifecycle
- **WHEN** a work item is created, a next action completed and undone, an update added, the item archived, restored, and deleted
- **THEN** the performance collection, records, and accomplishments SHALL contain no new or changed documents

#### Scenario: Security rules
- **WHEN** an authenticated user reads or writes `todos/{userId}/work`
- **THEN** access SHALL be allowed only when the user's uid equals `{userId}`, as the existing rules already provide
