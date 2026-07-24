## ADDED Requirements

### Requirement: Add conversation log entry
The system SHALL allow users to add dated conversation log entries to any person record.

#### Scenario: Add log with default date
- **WHEN** user opens a person and taps "Add Log Entry"
- **THEN** a form appears with a text field and a date picker
- **AND** the date picker defaults to today
- **AND** user enters text and confirms
- **AND** the log entry is saved with the specified date

#### Scenario: Add log with custom date
- **WHEN** user adds a log entry and changes the date in the date picker
- **THEN** the log is saved with the custom date

#### Scenario: Add log with free-form text
- **WHEN** user enters multi-line text in the log entry field
- **THEN** the text is saved exactly as entered
- **AND** examples: "Talked about his favorite baseball team - the Mets", "Told me he likes apple pie", "I told him I'm looking for a job"

### Requirement: View conversation logs in reverse chronological order
The system SHALL display conversation logs most recent first, with date and entry text visible.

#### Scenario: View logs for a person
- **WHEN** user opens a person detail page
- **THEN** conversation logs are displayed below the static info
- **AND** most recent log appears first
- **AND** each log shows the date and full entry text

#### Scenario: View logs with varying dates
- **WHEN** logs span multiple months or years
- **THEN** older logs appear lower in the list
- **AND** dates are displayed in readable format (e.g., "May 20, 2026")

### Requirement: Edit conversation log entry
The system SHALL allow users to edit the text and date of any log entry.

#### Scenario: Edit log text
- **WHEN** user taps a log entry to edit
- **THEN** the entry text appears in an editable field
- **AND** user can modify the text and save changes
- **AND** the modified timestamp updates

#### Scenario: Edit log date
- **WHEN** user edits a log entry
- **THEN** the date can be changed via a date picker
- **AND** the log maintains its position in reverse chronological order after changes

### Requirement: Delete conversation log entry
The system SHALL allow users to delete individual conversation log entries.

#### Scenario: Delete log
- **WHEN** user opens a log entry and taps "Delete"
- **THEN** a confirmation dialog appears
- **AND** upon confirmation, the log entry is removed
- **AND** the person's other logs remain intact

### Requirement: Timestamp metadata
The system SHALL track when each log entry was created and last updated.

#### Scenario: Created and updated timestamps
- **WHEN** a log entry is created
- **THEN** it has a createdAt timestamp (server time)
- **AND** it has an updatedAt timestamp (initially equal to createdAt)

#### Scenario: Updated timestamp changes
- **WHEN** a log entry is edited
- **THEN** the updatedAt timestamp is refreshed
- **AND** createdAt remains unchanged

### Requirement: "Last updated" person reference
The system SHALL track when a person's conversation logs were last modified for sorting purposes.

#### Scenario: Person last updated timestamp
- **WHEN** any log entry is added, edited, or deleted for a person
- **THEN** the person's lastUpdated timestamp is refreshed
- **AND** this timestamp is used when sorting people by "last updated"

#### Scenario: Sort by last updated
- **WHEN** user sorts the people list by "last updated"
- **THEN** people with the most recent log modifications appear first
