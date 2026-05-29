## ADDED Requirements

### Requirement: Contributions-style grid layout

The performance heatmap SHALL render task-completion history as a column-major grid where each column is one calendar week and each row is a day of the week. Columns MUST be ordered oldest on the left to newest on the right. The rightmost column MUST contain the current week.

#### Scenario: Grid orientation
- **WHEN** the performance page renders the heatmap for a user with at least one completed task in the visible range
- **THEN** the grid displays 7 rows (one per day-of-week) and N columns (one per week)
- **AND** the leftmost column represents the oldest visible week
- **AND** the rightmost column represents the week containing today

#### Scenario: Day-of-week ordering
- **WHEN** the heatmap renders
- **THEN** row 0 is Monday and row 6 is Sunday (matching the app's existing weekday convention)

### Requirement: Multi-month visible range

The heatmap SHALL display a rolling window of the most recent N months ending on the current week, where N is at least 3. The total number of week columns MUST equal ⌈N × 4.345⌉ (the average weeks per month), rounded to whole weeks, with the window aligned so the rightmost column ends on the current week.

#### Scenario: Default 3-month window
- **WHEN** the heatmap renders with the default range
- **THEN** approximately 13 week columns are shown
- **AND** the rightmost column contains today

#### Scenario: Range queries the service correctly
- **WHEN** the heatmap mounts
- **THEN** it requests performance data from the Monday of the oldest visible week through the Sunday of the current week
- **AND** uses `PerformanceService.streamPerformanceForMonth(userId, startDate, endDate)` with that range

### Requirement: Cell intensity reflects completion count

Each cell's fill color SHALL scale with the number of tasks completed on that day, using a fixed set of buckets from "no activity" to "high activity". Days with no Firestore record MUST render in the empty-bucket color (not blank).

#### Scenario: Color buckets
- **WHEN** a cell's day has a completion count `c`
- **THEN** the fill color is selected by bucket:
  - `c == 0` → empty (light grey)
  - `1 ≤ c < 2` → low
  - `2 ≤ c < 5` → medium-low
  - `5 ≤ c < 8` → medium-high
  - `c ≥ 8` → high
- **AND** the color palette uses the existing green ramp from the prior heatmap implementation

#### Scenario: Missing day renders empty
- **WHEN** the date range includes a day with no performance document in Firestore
- **THEN** the corresponding cell renders in the empty-bucket color

### Requirement: Future and out-of-range cells are hidden

Cells representing dates after today, or dates earlier than the oldest visible week's Monday, SHALL render as empty (transparent) placeholders so the grid remains rectangular without misrepresenting data.

#### Scenario: Days after today in the current week
- **WHEN** today is Wednesday
- **THEN** the Thursday–Sunday rows of the rightmost column render as transparent placeholders, not as zero-activity cells

### Requirement: Month boundary labels

The heatmap SHALL render text labels above the columns indicating which weeks correspond to each calendar month, so the user can locate themselves in time. Labels MUST appear only at columns where the month changes from the prior column.

#### Scenario: Label placement
- **WHEN** column index `i` is the first column whose Monday falls in a different calendar month than column `i-1`
- **THEN** the abbreviated month name (e.g., "Apr") is rendered above that column

### Requirement: Empty-state handling

When the user has no completed tasks in the visible range, the heatmap SHALL still render the full grid in the empty-bucket color rather than showing a "no data" message. The surrounding page MAY show empty-state messaging for the lists below the heatmap independently.

#### Scenario: New user
- **WHEN** the user has zero performance documents in the visible range
- **THEN** the heatmap renders a full grid of empty-bucket cells with month labels intact

### Requirement: Day-of-week row labels

The heatmap SHALL render compact day-of-week labels (e.g., "M", "W", "F") to the left of the grid, aligned with their rows. Labels MUST be readable but unobtrusive.

#### Scenario: Label rendering
- **WHEN** the heatmap renders
- **THEN** the Monday, Wednesday, and Friday rows have a leading label; other rows MAY be unlabeled to reduce visual clutter
