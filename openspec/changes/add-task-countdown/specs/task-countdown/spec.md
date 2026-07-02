## ADDED Requirements

### Requirement: Mark a task as a countdown

The system SHALL provide a "Countdown" toggle in the Advanced section of the task create/edit form. The task's countdown state SHALL be persisted as a boolean on the task and SHALL default to `false` for existing and newly created tasks that do not set it.

#### Scenario: Enabling countdown on a task with a due date
- **WHEN** the user enables the Countdown toggle on a task that has a due date and saves
- **THEN** the task is persisted with `countdown = true`
- **AND** an entry for the task appears in the user's countdown index with the task's title and due date

#### Scenario: Countdown defaults off
- **WHEN** a task is created without interacting with the Countdown toggle
- **THEN** the task is persisted with `countdown = false`
- **AND** no countdown index entry is created for it

#### Scenario: Disabling countdown on an existing task
- **WHEN** the user disables the Countdown toggle on a task that previously had it enabled and saves
- **THEN** the task is persisted with `countdown = false`
- **AND** the task's countdown index entry is removed

### Requirement: Countdown requires a due date

The system SHALL only surface a countdown for a task that has a due date. A task with countdown enabled but no due date SHALL NOT produce a countdown chip or index entry.

#### Scenario: Countdown enabled without a due date
- **WHEN** a task has countdown enabled but no due date is set
- **THEN** no countdown index entry is created
- **AND** no chip is rendered for that task

### Requirement: Display countdown chips in the task list header

The system SHALL render countdown chips in a single wrapping row at the top of the task list day view, positioned directly above the day's points display. The chip row SHALL be omitted entirely when there are no active countdowns for the viewed day. Chips SHALL use the application's primary accent color.

#### Scenario: Chips render above the points
- **WHEN** the user views a day and one or more countdown tasks have a due date after the viewed day
- **THEN** a row of countdown chips is shown above the day's points
- **AND** each chip displays the task title and the number of days from the viewed day until that task's due date

#### Scenario: Chips are global across day views
- **WHEN** the user navigates to any day in the task list
- **THEN** countdown chips for future-dated countdown tasks are shown regardless of which day is being viewed
- **AND** the day count on each chip is measured from the currently viewed day to the task's due date

#### Scenario: Multiple chips wrap
- **WHEN** the number of countdown chips exceeds the available width
- **THEN** the chips remain in a single row until it is full and wrap onto additional rows only on overflow

#### Scenario: No active countdowns
- **WHEN** no countdown tasks have a due date after the viewed day
- **THEN** no chip row and no empty gap is shown above the points

### Requirement: Countdown chips disappear at zero

The system SHALL show a countdown chip only while the number of days from the viewed day to the task's due date is greater than zero. When the viewed day is on or after the task's due date, the chip SHALL NOT be shown.

#### Scenario: Viewing the due date day
- **WHEN** the viewed day equals the countdown task's due date
- **THEN** the chip for that task is not shown

#### Scenario: Paging forward reduces the count
- **WHEN** the user pages the day view forward toward a countdown task's due date
- **THEN** the day count on that task's chip decreases accordingly
- **AND** the chip disappears once the viewed day reaches or passes the due date

### Requirement: Countdown index stays consistent with task state

The system SHALL keep the countdown index consistent with task changes. Completing or deleting a countdown task SHALL remove its countdown index entry, and updating a countdown task's due date SHALL update the entry.

#### Scenario: Completing a countdown task
- **WHEN** a countdown task is marked complete
- **THEN** its countdown index entry is removed
- **AND** its chip no longer appears in the task list header

#### Scenario: Deleting a countdown task
- **WHEN** a countdown task is deleted
- **THEN** its countdown index entry is removed

#### Scenario: Changing the due date of a countdown task
- **WHEN** a countdown task's due date is changed and saved
- **THEN** its countdown index entry reflects the new due date
- **AND** the chip's day count is recalculated from the new due date
