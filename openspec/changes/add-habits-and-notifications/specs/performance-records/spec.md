## ADDED Requirements

### Requirement: Records card on the Performance tab
The system SHALL show a "Records" stats card at the bottom of the Performance tab presenting all-time achievements, without changing the existing average/points-over-time/heatmap views.

#### Scenario: Highest daily score
- **WHEN** the Records card is shown
- **THEN** it displays the highest single-day score ever achieved and the date it was achieved

#### Scenario: Longest streak
- **WHEN** the Records card is shown and the user has habits
- **THEN** it displays the longest streak achieved across all habits, the habit's name, and the date it was last completed

#### Scenario: Records reflect all-time data, not just the visible window
- **WHEN** the highest score occurred outside the chart's current time window
- **THEN** the Records card still reflects it (records are derived from full history / persisted, not only the on-screen range)

#### Scenario: Graceful when empty
- **WHEN** there is no performance history or no habits yet
- **THEN** the card shows sensible empty values instead of erroring
