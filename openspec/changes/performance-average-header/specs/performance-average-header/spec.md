## ADDED Requirements

### Requirement: Header displays rolling-average points

The performance page SHALL render a header above all other content showing the user's rolling average of daily `completed.ALL` points for a currently-selected time window. The numeric value MUST be formatted to exactly 2 decimal places (e.g., `3.40`, not `3.4` or `3`). The window label MUST be visible alongside the value.

#### Scenario: Default window on page load
- **WHEN** the performance page mounts
- **THEN** the header displays the 7-day rolling average labeled "Last 7 days"
- **AND** the numeric value is formatted to 2 decimal places

#### Scenario: Two-decimal formatting
- **WHEN** the computed average is an integer (e.g., 4)
- **THEN** the display reads "4.00", not "4" or "4.0"

#### Scenario: Zero formatting
- **WHEN** the average is exactly zero
- **THEN** the display reads "0.00"

### Requirement: Average divides total points by total calendar days

The average SHALL be computed as `sum(completed.ALL across window) / windowDays`, where `windowDays` is the count of calendar days in the window. Days with no Firestore performance document MUST count toward the denominator as zero-activity days. The numerator MUST NOT include days outside the window.

#### Scenario: Zero-activity days included in denominator
- **WHEN** the user has performance data for only 3 of the last 7 days
- **THEN** the average is `(sum of those 3 days) / 7`, not `sum / 3`

#### Scenario: Total points sum
- **WHEN** the user's last 7 days have points `[0, 2, 5, 0, 3, 0, 4]`
- **THEN** the average is `14 / 7 = 2.00`

### Requirement: Tap cycles through fixed windows

Tapping the header SHALL advance through four fixed windows in order: 7 days → 30 days → 90 days → 365 days. After the 365-day window, the next tap MUST return to 7 days, forming a cycle. Each window MUST be labeled clearly.

#### Scenario: Forward cycle
- **WHEN** the user taps the header
- **THEN** the displayed window advances to the next in the sequence (7d → 30d → 90d → 365d → 7d)
- **AND** the label updates accordingly: "Last 7 days", "Last month", "Last 3 months", "Last year"

#### Scenario: Recomputed on cycle
- **WHEN** the window changes
- **THEN** the displayed average is recomputed using the new window's denominator and numerator

### Requirement: Year window clamps to longest available data

When the user has fewer than 365 calendar days of performance data, the 365-day window SHALL clamp its denominator to the number of calendar days between today and the user's oldest performance document. The numerator SHALL still be the sum over that clamped range.

#### Scenario: New user with 90 days of data
- **WHEN** the user's oldest performance document is 90 days ago and they cycle to the year window
- **THEN** the denominator is 90 (not 365)
- **AND** the numerator is the sum of all 90 days of data

#### Scenario: Long-tenured user
- **WHEN** the user has more than 365 days of data and cycles to the year window
- **THEN** the denominator is 365
- **AND** the numerator is the sum of the most recent 365 days

#### Scenario: Brand new user with one day of data
- **WHEN** the user has only today's data and cycles to the year window
- **THEN** the denominator is 1
- **AND** the average equals today's points

### Requirement: Header is visually distinct and prominent

The header SHALL appear as the first child of the performance page, visually distinct from the heatmap and other content, with the numeric average rendered larger than the surrounding labels. The tap affordance SHALL be discoverable (e.g., via ink response, subtle icon, or hint text).

#### Scenario: Layout position
- **WHEN** the performance page renders
- **THEN** the average header is the topmost content widget, above the heatmap

#### Scenario: Tap discoverability
- **WHEN** the header is rendered
- **THEN** it includes a visible affordance indicating it is interactive (e.g., a small icon or hint text)
