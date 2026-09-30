## ADDED Requirements

### Requirement: Markdown format for a work item
The system SHALL format a work item as Markdown with the following structure, using ISO dates (YYYY-MM-DD). Line 1 is a level-2 heading with the title. Line 2 is an italic line `_Created {date}_`, extended to `_Created {date}, archived {date}_` for archived items. Then a blank line, the notes paragraph, a blank line, a level-3 heading `Next actions` followed by one list item per next action, then a level-3 heading `Updates` followed by one list item per update formatted as `- {date}: {text}`.

Open actionable actions SHALL use `- [ ] {text}`; waiting actions SHALL append `  (waiting on {who})`; completed actions SHALL use `- [x]` and append `  (done {date})`. The Notes paragraph SHALL be omitted when notes are empty, and the Updates section SHALL be omitted when there are no updates. Next actions SHALL be listed in stored order.

#### Scenario: Full item
- **WHEN** an item has notes, one waiting action, one completed action, and one update
- **THEN** the output SHALL match the structure above with every section present

#### Scenario: Minimal item
- **WHEN** an item has only a title and no next actions, notes, or updates
- **THEN** the output SHALL contain the heading, the created line, and an empty "Next actions" section, with no Notes paragraph and no Updates section

#### Scenario: Archived item
- **WHEN** the item is archived
- **THEN** the created line SHALL include `, archived {date}`

### Requirement: Markdown format for the board
The system SHALL format the whole board as a `# Work` section containing every active item in board order, followed by a `# Archived` section containing every archived item newest first, preceded by a single line `_Exported {date}_`. Sections with no items SHALL still be present with the heading and the line `_None_`.

#### Scenario: Board with both sections
- **WHEN** there are two active and one archived item
- **THEN** the output SHALL have the exported line, `# Work` with the two items in position order, then `# Archived` with the one item

#### Scenario: No archived items
- **WHEN** there are no archived items
- **THEN** the `# Archived` section SHALL contain `_None_`

### Requirement: Copy to clipboard
The system SHALL provide "Copy as Markdown" on the item detail page (active or archived) and "Copy all as Markdown" in the Work page app bar. Each SHALL write the formatted text to the system clipboard and confirm with a snackbar. Export SHALL make no network calls beyond the reads already needed to display the data.

#### Scenario: Copy single item
- **WHEN** the user taps "Copy as Markdown" on an item
- **THEN** the clipboard SHALL contain that item's Markdown and a confirmation snackbar SHALL appear

#### Scenario: Copy all
- **WHEN** the user taps "Copy all as Markdown"
- **THEN** the clipboard SHALL contain the board Markdown including archived items

### Requirement: Stable format
The system SHALL keep the export format stable, verified by golden-string tests, so that any change to the format is deliberate and reflected in this spec.

#### Scenario: Golden test
- **WHEN** the export functions are run against fixed fixture items
- **THEN** the output SHALL equal the committed golden strings exactly
