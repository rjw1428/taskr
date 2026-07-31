# subtask-scheduling Specification

## Purpose
TBD - created by archiving change add-subtasks. Update Purpose after archive.
## Requirements
### Requirement: A scheduled subtask appears on its day with the parent's title
The system SHALL display a subtask that has a due date as an ordinary task row on that day's to-do list, and that row SHALL also show the parent task's title.

#### Scenario: Scheduled subtask on the to-do list
- **WHEN** a subtask has a due date of a given day
- **THEN** it appears as a regular task row on that day's to-do list
- **AND** the row shows both the subtask's own title and its parent's title (e.g. "Book venue · Plan Q3 offsite")

### Requirement: The backlog shows a parent with its children, including scheduled ones
The system SHALL, in the backlog, display each parent with its children nested beneath it. Children that have been scheduled to a date SHALL still appear under the parent, annotated with their date. There SHALL be a single record per subtask shared by the backlog and the day view (no duplicated records).

#### Scenario: Backlog nesting with mixed scheduling
- **WHEN** a parent has some unscheduled children and some children scheduled to dates
- **THEN** the backlog shows the parent with all of its children nested beneath it
- **AND** each scheduled child is shown with a date indicator

#### Scenario: A change to a subtask is reflected in both views
- **WHEN** the user changes or completes a subtask from either the to-do list or the backlog
- **THEN** the change is reflected in both views without any separate synchronization
- **AND** no duplicate copy of the subtask is created

### Requirement: Assigning a date to a parent cascades to its unassigned children
The system SHALL, when a date is assigned to a parent, move only that parent's **unassigned** children to that date. Children that already have their own date and children that are completed SHALL NOT be moved.

#### Scenario: Cascade moves only unassigned children
- **WHEN** the user assigns a date to a parent that has unassigned children, hand-dated children, and completed children
- **THEN** the unassigned children are moved to the assigned date
- **AND** the hand-dated children keep their own dates
- **AND** the completed children are not moved

### Requirement: Pushing carries the remainder
The system SHALL push a subtask like any other task, moving only that subtask; completed siblings SHALL NOT move.

#### Scenario: Push an incomplete subtask
- **WHEN** the user pushes an incomplete subtask
- **THEN** that subtask moves to the next day
- **AND** its completed sibling subtasks stay on their current day

#### Scenario: Completed steps stay recorded
- **WHEN** a subtask has already been completed
- **THEN** it remains on the day it was completed and is unaffected by pushing its siblings

