## ADDED Requirements

### Requirement: Tasks have an optional goal association
The Task model SHALL include an optional `goalId` field. When present, it links the task to its parent goal. Goal-generated tasks SHALL be stored in the standard task collection (`todos/{userId}/tasks/{date}/items/`) alongside manually created tasks.

#### Scenario: Goal-generated task has goalId
- **WHEN** the system generates a task from a goal
- **THEN** the task document includes `goalId` set to the parent goal's ID

#### Scenario: Manually created tasks have no goalId
- **WHEN** a user creates a task manually via the Add Task form
- **THEN** the task document has `goalId` set to null

### Requirement: Goal tasks are visually distinguished in the task list
The system SHALL visually indicate when a task is linked to a goal. The task item SHALL display a goal indicator (icon or label) showing the parent goal's title.

#### Scenario: Goal task appears in daily task list
- **WHEN** the user views their daily task list containing both regular and goal-linked tasks
- **THEN** goal-linked tasks display a visual goal indicator with the goal's title, distinguishing them from regular tasks

#### Scenario: Goal task from deleted goal
- **WHEN** a completed task's parent goal has been deleted
- **THEN** the task still displays but the goal indicator shows the goal title without a navigation action

### Requirement: User can navigate to goal from a task
The system SHALL add a "View Goal" action to the popup menu of any task that has a `goalId`. Tapping it SHALL navigate to the goal's detail page.

#### Scenario: View Goal action on goal task
- **WHEN** the user opens the popup menu on a task with a `goalId`
- **THEN** the menu includes a "View Goal" option in addition to the standard actions (Edit, Remove, Push)

#### Scenario: Tapping View Goal navigates to goal detail
- **WHEN** the user taps "View Goal" from a task's popup menu
- **THEN** the system navigates to the goal detail page for that task's parent goal

#### Scenario: View Goal not shown on regular tasks
- **WHEN** the user opens the popup menu on a task without a `goalId`
- **THEN** the menu does not include a "View Goal" option

### Requirement: Deleting a goal cascades to future uncompleted tasks
The system SHALL delete all uncompleted tasks linked to a goal when that goal is deleted. Completed tasks SHALL be preserved with their `goalId` intact for historical purposes.

#### Scenario: Cascade delete removes future uncompleted tasks
- **WHEN** a user deletes a goal that has tasks across multiple future dates
- **THEN** the system queries all tasks with matching `goalId` where `completed == false`, deletes them, and removes their IDs from task ordering arrays

#### Scenario: Completed tasks survive goal deletion
- **WHEN** a user deletes a goal that has both completed and uncompleted tasks
- **THEN** completed tasks remain in their date partitions with `goalId` preserved

### Requirement: Goal tasks participate in normal task operations
Goal-linked tasks SHALL support all standard task operations: completion, push/reschedule, reordering, and editing. Completing a goal task SHALL update the corresponding generation record's `completedTaskIds`.

#### Scenario: Complete a goal task
- **WHEN** the user marks a goal-linked task as completed
- **THEN** the task's `completed` field is set to true, `completedTime` is recorded, confetti fires, and the generation record is updated with this task ID in `completedTaskIds`

#### Scenario: Push a goal task to tomorrow
- **WHEN** the user pushes a goal-linked task
- **THEN** the task is moved to the next day following the standard push behavior, with `goalId` preserved

#### Scenario: Goal tasks count toward performance score
- **WHEN** a goal-linked task is completed
- **THEN** it contributes to the daily performance score identically to any other task
