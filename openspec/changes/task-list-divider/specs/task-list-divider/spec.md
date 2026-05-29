## ADDED Requirements

### Requirement: Divider data model
The system SHALL support a `type` field on the Task model with values `task` (default) or `divider`. Dividers SHALL have an optional `title` (label), `id`, `type`, and `added` timestamp. The `title` MAY be empty, resulting in a plain horizontal rule with no text. All other Task fields SHALL be optional and unused for dividers.

#### Scenario: Existing tasks without type field
- **WHEN** a Task document is loaded from Firestore without a `type` field
- **THEN** the system SHALL default `type` to `task`

#### Scenario: Divider document structure
- **WHEN** a divider is created with label "Morning Routine"
- **THEN** the system SHALL store a document with `type: "divider"`, `title: "Morning Routine"`, `added` timestamp, and `completed: false`

### Requirement: Create divider via long-press
The system SHALL create a new divider when the user long-presses the FAB (add task) button on the task list screen. The system SHALL trigger haptic feedback (`HapticFeedback.mediumImpact()`) when the long-press is recognized. The system SHALL prompt the user for a label via a dialog before creating the divider.

#### Scenario: Long-press creates divider with label
- **WHEN** the user long-presses the FAB on the task list screen
- **THEN** the system SHALL trigger haptic feedback AND display a dialog prompting for a divider label

#### Scenario: Divider created after label entry
- **WHEN** the user enters a label and confirms the dialog
- **THEN** the system SHALL create a divider at the end of the current task list with the provided label

#### Scenario: Divider created with blank label
- **WHEN** the user confirms the dialog without entering a label
- **THEN** the system SHALL create a divider with an empty title, rendered as a plain horizontal rule

#### Scenario: Dialog cancelled
- **WHEN** the user dismisses the label dialog without confirming
- **THEN** the system SHALL NOT create a divider

### Requirement: Divider rendering
The system SHALL render dividers as a horizontal rule with the label text centered on it. Dividers SHALL be visually distinct from task items. Each divider SHALL display a remove button.

#### Scenario: Divider appears in task list with label
- **WHEN** the task list contains a divider with a non-empty label
- **THEN** the system SHALL render a horizontal line with the divider's label centered on it, and a remove (X) button

#### Scenario: Divider appears in task list without label
- **WHEN** the task list contains a divider with an empty label
- **THEN** the system SHALL render a plain horizontal line with a remove (X) button

#### Scenario: Divider does not affect progress
- **WHEN** the task list contains dividers
- **THEN** dividers SHALL NOT be counted in the daily progress score calculation

### Requirement: Divider reordering
Dividers SHALL participate in the same drag-and-drop reordering system as tasks. Dividers SHALL have a drag handle and be movable to any position in the list.

#### Scenario: Drag divider to new position
- **WHEN** the user drags a divider from position 3 to position 1
- **THEN** the system SHALL update the `taskOrder` array to reflect the new position

### Requirement: Divider removal
The system SHALL allow users to remove a divider by tapping the remove button on the divider item. Removal SHALL delete the divider document from Firestore and remove its ID from the `taskOrder` array. The system SHALL show a snackbar with an "Undo" action to restore the divider, matching the existing task deletion pattern.

#### Scenario: Remove divider
- **WHEN** the user taps the remove button on a divider
- **THEN** the system SHALL delete the divider from Firestore, remove it from the `taskOrder` array, AND display a snackbar with an "Undo" action

#### Scenario: Undo divider removal
- **WHEN** the user taps "Undo" on the divider removal snackbar
- **THEN** the system SHALL restore the divider document and its position in the `taskOrder` array

### Requirement: Long-press on backlog FAB
The system SHALL also support creating dividers via long-press on the backlog FAB.

#### Scenario: Long-press backlog FAB
- **WHEN** the user long-presses the FAB on the backlog screen
- **THEN** the system SHALL trigger haptic feedback AND create a divider in the backlog list following the same flow as the task list
