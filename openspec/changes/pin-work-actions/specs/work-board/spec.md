## MODIFIED Requirements

### Requirement: Work item data model
The system SHALL store work items as documents in `todos/{userId}/work` with fields `title` (non-empty string), `notes` (string, may be empty), `position` (integer sort key), `nextActions` (list of next action maps), `updates` (list of progress update maps), `createdAt` and `lastUpdated` (epoch milliseconds). Each next action SHALL have a client-generated stable `id`, `text`, optional `waitingOn` string, `createdAt`, nullable `completedAt`, and nullable `pinnedAt` (epoch milliseconds, non-null when the action is pinned). Work items SHALL NOT carry effort, points, dates, tags, or recurrence.

#### Scenario: Creating a work item
- **WHEN** the user saves a new work item with title "Migrate billing service"
- **THEN** the system SHALL write a document under `todos/{userId}/work` with that title, empty notes, empty `updates`, `createdAt` and `lastUpdated` set to now, and `position` equal to the current count of active items

#### Scenario: Document id is not stored as a field
- **WHEN** a work item is written or updated
- **THEN** the payload SHALL NOT contain an `id` field; the document id is the identity

#### Scenario: Missing optional fields on read
- **WHEN** a stored document lacks `notes`, `updates`, or `nextActions`
- **THEN** the model SHALL load with empty string or empty list defaults instead of failing

#### Scenario: New next actions start unpinned
- **WHEN** a next action is created
- **THEN** its `pinnedAt` SHALL be null

#### Scenario: Pin state round-trips
- **WHEN** a next action with a non-null `pinnedAt` is read and written back by an unrelated mutation (edit text, complete, undo)
- **THEN** `pinnedAt` SHALL be preserved unchanged
