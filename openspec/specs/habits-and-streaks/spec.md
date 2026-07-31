# habits-and-streaks Specification

## Purpose
TBD - created by archiving change add-habits-and-notifications. Update Purpose after archive.
## Requirements
### Requirement: Create and manage habits from the Goals tab
The system SHALL let the user create habits manually (no AI) from the Goals tab, each with a title, a cadence (daily / weekly on chosen weekdays / monthly), an Effort level (default Low), and an optional reminder. Habits SHALL be pausable and deletable.

#### Scenario: Create a habit
- **WHEN** the user creates a habit with a cadence
- **THEN** a habit is saved and its task instances begin appearing on the scheduled days
- **AND** no AI/goal generation is involved

#### Scenario: Pause and delete
- **WHEN** the user pauses a habit
- **THEN** no new instances are materialized until it is resumed
- **WHEN** the user deletes a habit
- **THEN** its future incomplete instances are removed and already-completed instances remain as history

### Requirement: Habits materialize as recurring task instances
The system SHALL back each habit with real task instances generated on its cadence, reusing the existing recurring-task generation. Because habits are open-ended, the system SHALL keep upcoming instances materialized via a rolling top-up rather than a fixed end date.

#### Scenario: Instances appear on their scheduled days
- **WHEN** a habit's cadence includes a given day
- **THEN** a task instance for that habit appears on that day's to-do list, carrying the habit's Effort

#### Scenario: Rolling materialization
- **WHEN** the user opens the app and upcoming instances are running low
- **THEN** the system tops up the next window of scheduled instances without duplicating existing ones

### Requirement: Each habit instance shows its current streak
The system SHALL display the habit's current streak on its task instances (e.g. a "🔥 N" badge).

#### Scenario: Streak badge on the card
- **WHEN** a habit task instance is shown
- **THEN** it displays the habit's current streak count

#### Scenario: Streak reflects a lapse without the user acting
- **WHEN** a scheduled occurrence has passed uncompleted since the last completion
- **THEN** the displayed streak is 0 (the chain is broken), even before any new interaction

### Requirement: Streak counts consecutive completed scheduled occurrences
The system SHALL compute a habit's streak as the number of consecutive most-recent scheduled occurrences that were completed, resetting on the first missed scheduled occurrence. Today's occurrence, if not yet completed, SHALL be treated as pending (not a miss).

#### Scenario: Daily habit
- **WHEN** a daily habit was completed the last 5 days in a row
- **THEN** its streak is 5
- **WHEN** a due day was missed
- **THEN** the streak resets

#### Scenario: Day-of-week habit
- **WHEN** a Mon/Wed/Fri habit had Monday and Wednesday completed but Friday missed
- **THEN** the streak reset at Friday (Tue/Thu are not scheduled occurrences and are ignored)

### Requirement: Habits score like tasks; streaks never affect the score
The system SHALL award the habit's Effort points when a habit instance is completed, through the existing task-completion scoring. The streak SHALL NOT contribute any points, multiplier, or bonus to the daily score.

#### Scenario: Completing a habit scores its effort
- **WHEN** the user completes a habit instance with Effort = Low
- **THEN** the daily score increases by the Low point value (1), the same as any Low task

#### Scenario: A long streak adds nothing to the score
- **WHEN** a habit has a long streak
- **THEN** the streak length adds no points to the daily score; only completing the instance does

