## ADDED Requirements

### Requirement: User can create a goal
The system SHALL allow authenticated users to create a goal by providing a title (required), optional description, timeframe, and frequency. The goal form SHALL be presented as a modal bottom sheet accessible from the Goals tab FAB.

#### Scenario: Create a goal with all fields
- **WHEN** the user fills in title "Learn the piano", description "Focus on classical pieces", timeframe "6 months", frequency "daily", and taps Save
- **THEN** the system creates a goal document at `todos/{userId}/goals/{goalId}` with status `active`, `startDate` set to today, and `endDate` computed as today + 6 months

#### Scenario: Create a goal with minimum fields
- **WHEN** the user fills in only the title "Be a better friend" and leaves other fields at defaults
- **THEN** the system creates the goal with the default timeframe and frequency, status `active`

#### Scenario: Create a goal with N-times-per-week frequency
- **WHEN** the user selects frequency "N times/week" and sets the count to 3
- **THEN** the system stores `frequency: n_times_week` and `frequencyCount: 3` on the goal document

### Requirement: User can view their goals
The system SHALL display a list of the user's active goals on the Goals tab. Each goal item SHALL show the title, timeframe remaining, and frequency.

#### Scenario: View goals list with active goals
- **WHEN** the user navigates to the Goals tab and has 3 active goals
- **THEN** the system displays all 3 goals with their title, time remaining (e.g., "4 months left"), and frequency

#### Scenario: View goals list with no goals
- **WHEN** the user navigates to the Goals tab and has no goals
- **THEN** the system displays an empty state prompting the user to create their first goal

### Requirement: User can view goal details
The system SHALL provide a goal detail page showing the goal's full information, progress summary, and associated task history.

#### Scenario: View goal detail page
- **WHEN** the user taps on a goal in the goals list
- **THEN** the system displays the goal title, description, timeframe, frequency, start date, end date, weeks elapsed, total tasks generated, tasks completed, and completion rate

### Requirement: User can edit a goal
The system SHALL allow users to edit a goal's title, description, timeframe, and frequency. Timeframe changes SHALL recompute the `endDate`. Changes take effect on the next task generation cycle; already-generated tasks for the current week are not modified.

#### Scenario: Edit goal timeframe
- **WHEN** the user changes a goal's timeframe from "1 year" to "6 months"
- **THEN** the system recomputes `endDate` as `startDate + 6 months` and saves the updated goal

#### Scenario: Edit goal title
- **WHEN** the user changes a goal's title from "Learn piano" to "Learn classical piano"
- **THEN** the system updates the title and the next generation cycle uses the new title in its LLM prompt

### Requirement: User can delete a goal
The system SHALL allow users to delete a goal. Deletion SHALL set the goal's status to `deleted` and remove all future uncompleted tasks linked to that goal. Completed tasks SHALL be preserved.

#### Scenario: Delete a goal with future tasks
- **WHEN** the user deletes a goal that has 3 completed tasks and 4 uncompleted future tasks
- **THEN** the system sets goal status to `deleted`, deletes the 4 uncompleted tasks, and preserves the 3 completed tasks

#### Scenario: Confirm before deleting
- **WHEN** the user taps "Delete Goal"
- **THEN** the system displays a confirmation dialog before proceeding with deletion

### Requirement: Goal auto-completes with summary on expiry
The system SHALL automatically mark a goal as `completed` when its `endDate` has passed. The goal detail page SHALL display a completion summary including total tasks completed, total tasks generated, weeks active, and completion rate.

#### Scenario: Goal reaches end date
- **WHEN** a goal's `endDate` passes and the goal status is still `active`
- **THEN** the system sets status to `completed` and the goal detail page shows the completion summary

#### Scenario: View completed goal summary
- **WHEN** the user opens a completed goal's detail page
- **THEN** the system displays: weeks active, tasks completed out of total generated, and completion percentage
