## ADDED Requirements

### Requirement: System generates tasks from a goal on creation
The system SHALL generate the first week's worth of tasks immediately when a user creates a goal. Generation SHALL use Firebase VertexAI (gemini-1.5-flash) with a structured prompt containing the goal definition and frequency settings. The LLM response SHALL be parsed as JSON and converted into Task documents distributed across the appropriate daily date partitions.

#### Scenario: Initial task generation for a daily goal
- **WHEN** a user creates a goal with title "Study for flight exam", frequency "daily", and timeframe "1 month"
- **THEN** the system calls VertexAI with the goal context and creates 7 tasks (one per day) in `todos/{userId}/tasks/{date}/items/` for the next 7 days, each with `goalId` set to the new goal's ID

#### Scenario: Initial task generation for N-times-per-week goal
- **WHEN** a user creates a goal with frequency "3 times/week"
- **THEN** the system generates 3 tasks distributed across the coming week's days

#### Scenario: Initial task generation for auto-frequency goal
- **WHEN** a user creates a goal with frequency "auto"
- **THEN** the LLM determines the appropriate number and distribution of tasks for the week based on the goal's nature and timeframe

#### Scenario: LLM response fails to parse
- **WHEN** the VertexAI response is not valid JSON or doesn't match the expected task schema
- **THEN** the system retries once with a stricter prompt, and if still failing, shows an error to the user and logs the failure

### Requirement: System generates tasks weekly via Cloud Function
The system SHALL run a Cloud Function `generateGoalTasks` on schedule (`every sunday 20:00`) that generates the next week's tasks for all active goals across all users.

#### Scenario: Weekly generation for active goals
- **WHEN** the `generateGoalTasks` function fires on Sunday at 8 PM
- **THEN** for each user with active goals, the system generates tasks for each goal where `endDate > now`, writes tasks to the appropriate date partitions, and creates a generation record

#### Scenario: Weekly generation skips expired goals
- **WHEN** a goal's `endDate` has passed
- **THEN** the weekly generation function skips that goal and does not generate new tasks

#### Scenario: Weekly generation skips deleted goals
- **WHEN** a goal has status `deleted`
- **THEN** the weekly generation function skips that goal

### Requirement: Task generation uses completion history as context
The system SHALL include the history of completed and skipped tasks from prior generation cycles in the LLM prompt. This allows the LLM to build progressively on prior work and avoid repeating tasks.

#### Scenario: Second week generation with history
- **WHEN** generating tasks for week 2 of a goal, and week 1 had 5 tasks (3 completed, 2 skipped)
- **THEN** the LLM prompt includes the 3 completed task titles/descriptions and the 2 skipped task titles, along with the current week number relative to goal start

#### Scenario: Generation after many weeks
- **WHEN** generating tasks for week 12 of a goal with extensive history
- **THEN** the system includes a summarized history (recent 2-3 weeks in detail, older weeks as aggregated stats) to stay within prompt size limits

### Requirement: Generation records are persisted
The system SHALL store each generation cycle as a document at `todos/{userId}/goals/{goalId}/generations/{generationId}` containing: timestamp, week range, generated task IDs, the prompt sent, and the raw LLM response.

#### Scenario: Generation record created after weekly run
- **WHEN** the weekly generation function successfully creates tasks for a goal
- **THEN** a generation record is written with `generatedAt`, `weekStart`, `weekEnd`, `taskIds`, `prompt`, and `response` fields

#### Scenario: Generation record updated with completion data
- **WHEN** a task linked to a goal is marked as completed
- **THEN** the corresponding generation record's `completedTaskIds` array is updated to include that task's ID

### Requirement: User can manually regenerate tasks
The system SHALL allow users to trigger task regeneration from the goal detail page. Regeneration SHALL delete remaining uncompleted tasks for the current week and generate a fresh batch via VertexAI.

#### Scenario: Manual regeneration replaces uncompleted tasks
- **WHEN** the user taps "Regenerate" on a goal that has 2 completed and 3 uncompleted tasks for the current week
- **THEN** the system deletes the 3 uncompleted tasks, calls VertexAI for new tasks, creates the new tasks, and updates the generation record

#### Scenario: Manual regeneration with all tasks completed
- **WHEN** the user taps "Regenerate" but all current week tasks are already completed
- **THEN** the system generates additional tasks for the remaining days of the week without deleting any completed tasks
