## Why

The performance page currently shows a contributions grid, a list of accomplishments, and a line chart — all detail-level views. There's no top-line number that answers the question "how am I doing lately?" at a glance.

A header showing the rolling average of daily points gives the user an immediate, comparable metric. Making it tap-cyclable across windows (7d → 1m → 3m → 1y) lets the user contextualize today's pace against the recent past without needing a separate analytics screen. Two decimal places keep small movements visible (3.40 → 3.62 is a real shift; 3 → 4 would be lossy).

## Capabilities

### New Capabilities

- **performance-average-header** — Tappable header at the top of the performance page that displays the rolling average of daily `completed.ALL` points over a selectable window. Default window is 7 days; tapping cycles to 1 month (30d), then 3 months (90d), then 1 year (365d, clamped to longest available data). Average is shown to 2 decimal places.

### Modified Capabilities

<!-- None — no existing specs in openspec/specs/. -->

## Impact

- **Code modified:**
  - `lib/performance/performance_page.dart` — add the new header widget above the heatmap. May lift the date-range stream to a wider window or run a parallel query.
- **Code added:**
  - `lib/performance/performance_average_header.dart` — new stateful widget.
- **Code unchanged:**
  - `lib/services/performance.service.dart` — `streamPerformanceForMonth(userId, startDate, endDate)` is range-based and reusable as-is.
  - Firestore schema, security rules, cloud functions — no changes.
- **No new dependencies.**
