## Why

The current heatmap on the performance page renders a single calendar month — rows are weeks of that month, columns are days Mon→Sun. This makes it hard to perceive sustained effort over time: a productive Tuesday in early-month and a productive Tuesday this week sit in different rows, and last month disappears from view entirely at the rollover.

A GitHub-style contributions grid — columns are weeks oldest→newest, rows are days of the week — gives a continuous, scannable history. Streaks read as horizontal bands, gaps read as columns, and the user can see momentum across multiple months without switching views. This better serves the page's purpose: showing the user evidence of progress.

## Capabilities

### New Capabilities

- **performance-heatmap** — Multi-month contributions-style heatmap on the performance page. Columns are weeks ordered oldest (left) to newest (right). Rows are days of the week. Each cell's darkness scales with the count of tasks completed that day. The visible range spans a configurable number of months (default 3, i.e. ~12 columns) ending on the current week.

### Modified Capabilities

<!-- None — no existing specs in openspec/specs/. -->

## Impact

- **Code modified:**
  - `lib/performance/performance_heatmap.dart` — full rewrite of the grid layout and date math. Layout flips from row-major (week-of-month) to column-major (week index), with a wider date range.
  - `lib/performance/performance_page.dart` — minor: may need to widen the date range passed into the heatmap, or the heatmap may compute its own range.
- **Code unchanged:**
  - `lib/services/performance.service.dart` — `streamPerformanceForMonth(userId, startDate, endDate)` already accepts an arbitrary date range; reusable as-is despite its name.
  - Firestore schema, security rules, cloud functions — no changes.
- **Visual/UX:** Heatmap replaces month-grid; day-of-month numbers are dropped (cells become uniform squares). Month boundaries can optionally be marked with subtle labels under the bottom row.
- **No new dependencies.**
