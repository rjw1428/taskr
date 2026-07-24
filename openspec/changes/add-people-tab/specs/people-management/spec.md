## ADDED Requirements

### Requirement: Create a person with minimal information
The system SHALL allow users to create a person record with only a name. Additional fields (age, birthday, job, spouse, kids) are optional and can be added later.

#### Scenario: Create person with name only
- **WHEN** user navigates to People tab and taps "Add Person"
- **THEN** a form appears with a required "Name" field
- **AND** user can submit with just a name
- **AND** the person appears in the people list

#### Scenario: Create person with optional fields
- **WHEN** user creates a person and fills in age, birthday, job, spouse, or kids
- **THEN** these optional fields are stored with the person
- **AND** empty optional fields are not stored

### Requirement: View person details
The system SHALL display a person's static information (name, age, birthday, job, spouse, kids) in a sticky header, with conversation logs displayed below.

#### Scenario: View person with all fields
- **WHEN** user taps a person from the list
- **THEN** a detail page appears with all their information displayed
- **AND** static information is locked at the top
- **AND** conversation logs are displayed below in reverse chronological order

#### Scenario: View person with partial fields
- **WHEN** user opens a person who only has name and job filled in
- **THEN** only the filled-in fields are displayed (no empty placeholders)

### Requirement: Auto-age children
The system SHALL automatically age children based on their birthday or the anniversary of when they were added.

#### Scenario: Child with birthday
- **WHEN** a child has a birthday set (e.g., born March 15, 2012)
- **THEN** the system calculates their current age from the birthday
- **AND** age updates on each birthday

#### Scenario: Child without birthday
- **WHEN** a child is added with only name and age (e.g., "Maya, age 12" on July 20, 2026)
- **THEN** the system records the date added
- **AND** age increments by 1 on July 20 of each subsequent year
- **AND** age can be manually updated by editing the person

### Requirement: Edit person information
The system SHALL allow users to edit any field on a person record, including static info and adding/removing kids.

#### Scenario: Edit static information
- **WHEN** user taps "Edit" on a person detail page
- **THEN** a form appears with all current values pre-filled
- **AND** user can modify any field and save changes

#### Scenario: Add or remove kids
- **WHEN** user edits a person
- **THEN** user can add new kids to the kids list
- **AND** user can remove kids from the list
- **AND** changes are saved

### Requirement: Delete a person
The system SHALL allow users to delete a person record entirely.

#### Scenario: Delete person
- **WHEN** user opens a person and taps "Delete"
- **THEN** a confirmation dialog appears
- **AND** upon confirmation, the person and all their conversation logs are removed

### Requirement: View and search people list
The system SHALL display all people in a sortable list with name-based search.

#### Scenario: View people list
- **WHEN** user navigates to the People tab
- **THEN** all people appear in a list sorted by name (default) or by "last updated"

#### Scenario: Sort by name
- **WHEN** sort is set to "name"
- **THEN** people appear in alphabetical order

#### Scenario: Sort by last updated
- **WHEN** sort is set to "last updated"
- **THEN** people with the most recent conversation log entries appear first

#### Scenario: Search people by name
- **WHEN** user types in the search field
- **THEN** the list filters to show only people whose names match the search term (case-insensitive)

#### Scenario: Empty people list
- **WHEN** user has not added any people
- **THEN** the People tab shows an empty state with a prompt to "Add Person"
