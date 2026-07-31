## ADDED Requirements

### Requirement: Tasks can have one level of subtasks
The system SHALL allow a task to have child tasks ("subtasks"). A subtask SHALL itself be a task carrying a reference to its parent. Subtasks SHALL NOT have their own subtasks (exactly one level of nesting).

#### Scenario: Add a subtask to a task
- **WHEN** the user adds a subtask to a task
- **THEN** a new task is created that references the original task as its parent
- **AND** the new subtask behaves as a regular task (it can be scheduled, pushed, completed, prioritized, tagged, and reordered)

#### Scenario: Subtasks cannot nest further
- **WHEN** the user views a subtask
- **THEN** there is no option to add a subtask to it (nesting is limited to one level)

### Requirement: A task with children is a backlog-only container
The system SHALL treat any task that has at least one child as a container that appears only in the backlog and never as a row on a day's to-do list.

#### Scenario: Task converts to a container on first subtask
- **WHEN** a task that is scheduled on a day gains its first subtask
- **THEN** the parent no longer appears as a row on that day's to-do list
- **AND** the parent appears in the backlog as a container for its subtasks

#### Scenario: First child inherits the parent's date
- **WHEN** the first subtask is added to a task that had a due date
- **THEN** the new subtask inherits that due date
- **AND** the subtask appears on that day's to-do list so the work remains visible

#### Scenario: A childless task is unaffected
- **WHEN** a task has no subtasks
- **THEN** it behaves exactly as tasks do today (appears on its day and/or the backlog with no parent/child treatment)

### Requirement: Parent auto-completes and reopens with its children
The system SHALL automatically mark a parent complete when its last incomplete child is completed, and SHALL reopen a completed parent when a new (incomplete) child is added.

#### Scenario: Completing the last child completes the parent
- **WHEN** the user completes a subtask and it was the parent's only remaining incomplete child
- **THEN** the parent is marked complete

#### Scenario: Uncompleting a child reopens the parent
- **WHEN** a parent is complete and the user un-completes one of its children
- **THEN** the parent is marked incomplete again

#### Scenario: Adding a child to a completed parent reopens it
- **WHEN** the user adds a new subtask to a completed parent
- **THEN** the parent is reopened (marked incomplete)

### Requirement: Deleting a parent resolves its children
The system SHALL, when a parent is deleted, ask the user whether to delete the parent's children as well or keep them as standalone tasks.

#### Scenario: Delete parent and its steps
- **WHEN** the user deletes a parent and chooses to remove its steps
- **THEN** the parent and all of its subtasks are removed

#### Scenario: Delete parent but keep the steps
- **WHEN** the user deletes a parent and chooses to keep its steps
- **THEN** the parent is removed and each former subtask remains as a standalone task with no parent
