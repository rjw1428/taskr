## ADDED Requirements

### Requirement: Accomplishment queries are ordered and bounded at the source
The system SHALL order accomplishments newest-first in the Firestore query itself, and SHALL allow a caller to request at most a given number of accomplishments so that only the entries a view renders are fetched.

#### Scenario: Newest first without client-side sorting
- **WHEN** any caller subscribes to the accomplishment stream
- **THEN** entries arrive ordered by date descending, and the caller does not re-sort them

#### Scenario: Bounded request fetches only what is asked for
- **WHEN** a caller requests a limit of N accomplishments and more than N exist
- **THEN** the stream carries exactly N entries — the N most recent — and the remaining documents are not fetched

#### Scenario: Unbounded request still supported
- **WHEN** a caller requests the stream without specifying a limit
- **THEN** all accomplishments are returned, ordered newest-first

#### Scenario: Ordering is consistent with stored date format
- **WHEN** accomplishments are ordered by the stored `date` value
- **THEN** the resulting order is chronological, matching the order previously produced by sorting in the client

### Requirement: Performance tab summary fetches only what it displays
The system SHALL have the "Latest accomplishments" section on the Performance tab request only the number of accomplishments it renders, rather than fetching the full collection and truncating locally.

#### Scenario: Bounded fetch on the Performance tab
- **WHEN** the Performance tab is opened and the user has more accomplishments than the summary displays
- **THEN** only the displayed number of accomplishments is fetched from the server

#### Scenario: Displayed content is unchanged
- **WHEN** the summary renders
- **THEN** it shows the same most-recent accomplishments, in the same order and visual form, as before this change

#### Scenario: Summary remains live
- **WHEN** an accomplishment is created, edited, or deleted while the Performance tab is visible
- **THEN** the summary reflects the change without requiring a manual refresh

### Requirement: Accomplishment history is reachable from the Performance tab
The system SHALL provide an affordance in the "Latest accomplishments" section that opens a dedicated accomplishment history view.

#### Scenario: Opening history
- **WHEN** the user activates the affordance on the "Latest accomplishments" section
- **THEN** the accomplishment history view opens

#### Scenario: Returning to Performance
- **WHEN** the user navigates back from the history view
- **THEN** the Performance tab is restored and its summary still displays the most recent accomplishments

#### Scenario: Summary layout preserved
- **WHEN** the affordance is added
- **THEN** the rest of the Performance tab — the average header, charts, heatmap, and Records card — is unchanged in position and behavior

### Requirement: History view lists the full accomplishment log newest-first
The system SHALL present accomplishments in a dedicated full-height view, ordered newest-first, grouped under headings by the month in which they occurred.

#### Scenario: Chronological grouping
- **WHEN** the history view is displayed with accomplishments spanning several months
- **THEN** entries appear newest-first under a heading identifying the month and year of the entries beneath it

#### Scenario: Entry content
- **WHEN** an accomplishment is listed
- **THEN** it displays its difficulty score, title, and date, consistent with how the Performance tab summary presents an accomplishment

#### Scenario: Opening an entry
- **WHEN** the user selects an accomplishment in the history view
- **THEN** the existing accomplishment detail view opens for that accomplishment

#### Scenario: Empty history
- **WHEN** the user has no accomplishments
- **THEN** the history view shows an empty state rather than an error or a blank screen

#### Scenario: Scrolling is not nested
- **WHEN** the user scrolls the history view
- **THEN** the list scrolls as the view's primary scrolling region, without being confined to a fixed-height inner box

### Requirement: History loads incrementally as the user scrolls back
The system SHALL load an initial page of accomplishments and SHALL extend the loaded range as the user scrolls toward the end of the list, until the full history has been loaded.

#### Scenario: Initial page
- **WHEN** the history view first opens
- **THEN** it loads an initial page of the most recent accomplishments rather than the entire collection

#### Scenario: Extending on scroll
- **WHEN** the user scrolls near the end of the currently loaded entries and more accomplishments exist
- **THEN** the next page is loaded and appended, and the user can continue scrolling into older entries

#### Scenario: Loading feedback
- **WHEN** an additional page is being loaded
- **THEN** the view indicates that loading is in progress

#### Scenario: End of history
- **WHEN** every accomplishment has been loaded
- **THEN** scrolling further requests no additional pages and the view does not display a perpetual loading indicator

#### Scenario: Scroll position is preserved when a page arrives
- **WHEN** a newly loaded page is appended to the list
- **THEN** the user's scroll position is preserved and the content the user was reading does not jump

#### Scenario: History shorter than one page
- **WHEN** the user has fewer accomplishments than the initial page size
- **THEN** all are displayed and no additional page is requested

### Requirement: Loaded history stays live
The system SHALL keep the currently loaded range of the history view subscribed to updates, so that changes to any loaded accomplishment are reflected without reopening the view.

#### Scenario: Edit reflected in place
- **WHEN** the user edits an accomplishment that is currently loaded in the history view
- **THEN** the updated values appear in the list without reopening the view

#### Scenario: Deletion reflected in place
- **WHEN** an accomplishment currently loaded in the history view is deleted
- **THEN** it is removed from the list

#### Scenario: New accomplishment appears
- **WHEN** a new accomplishment is created while the history view is open
- **THEN** it appears at the top of the list, under the appropriate month heading

### Requirement: Detail view continues to track its accomplishment
The system SHALL preserve the accomplishment detail view's existing behavior of reflecting live updates and dismissing itself when its accomplishment is deleted, notwithstanding that callers may now subscribe to bounded accomplishment queries.

#### Scenario: Detail view opened from a bounded list
- **WHEN** the detail view is opened for an accomplishment reached from a view that fetched a limited set
- **THEN** the detail view displays that accomplishment's current values

#### Scenario: Deletion dismisses the detail view
- **WHEN** the accomplishment shown in the detail view is deleted
- **THEN** the detail view dismisses itself and returns to the view that opened it

#### Scenario: Edit reflected in the detail view
- **WHEN** the accomplishment shown in the detail view is edited
- **THEN** the detail view displays the updated values
