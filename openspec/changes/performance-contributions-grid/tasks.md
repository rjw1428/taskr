## 1. Date math helpers

- [x] 1.1 Add a private `_mondayOf(DateTime)` helper that normalizes any date to that week's Monday (00:00 local).
- [x] 1.2 Add a `_weekCount` constant (default 13) and compute `windowStart = _mondayOf(today) - (weekCount - 1) weeks` and `windowEnd = windowStart + (weekCount * 7) days - 1 day`.

## 2. Stream + data shaping

- [x] 2.1 Replace the current month-bounded `streamPerformanceForMonth` call with one using `windowStart` → `windowEnd`.
- [x] 2.2 Build a `Map<DateTime (date-only), int>` from the snapshot using the `completed.ALL` field, keyed by the date portion of each document's `date` timestamp.

## 3. Column-major layout

- [x] 3.1 Replace the existing `GridView.builder` with a horizontally-laid `Row` containing one `Column` per week (`weekCount` columns).
- [x] 3.2 Each week column renders 7 cell widgets, Monday at top, Sunday at bottom.
- [x] 3.3 Render cells for `cellDate > today` as a transparent `SizedBox` of the same dimensions so the grid stays rectangular.
- [x] 3.4 Drop the day-of-month number text inside cells; cells become uniform colored squares with rounded corners.

## 4. Color buckets

- [x] 4.1 Port the existing `_getColorForScore` thresholds (0 / <2 / <5 / <8 / ≥8) and the green ramp into the new widget.
- [x] 4.2 Keep the yellow "outstanding day" border for scores > 10.
- [x] 4.3 Cells with no Firestore record render in the empty-bucket color (light grey), not transparent.

## 5. Row + column labels

- [x] 5.1 Add a leading column of compact weekday labels (M, W, F shown; other rows blank) aligned with the day rows.
- [x] 5.2 Add a row of month labels above the grid. A label is emitted above column `i` when `month(_mondayOf(col_i)) != month(_mondayOf(col_{i-1}))`; always emit for column 0.
- [x] 5.3 Verify labels don't overlap on a typical phone width; tighten font size or omit weekday letters if so.

## 6. Empty state

- [x] 6.1 Remove the "No performance data for this month" message.
- [x] 6.2 When the snapshot is empty or null, still render the full grid (all cells in empty-bucket color) so the layout is stable.

## 7. Cleanup

- [x] 7.1 Remove the now-unused `daysInMonth`, `firstDayWeekday`, `adjustedFirstDayWeekday`, and `numberOfWeeks` calculations from the prior implementation.
- [x] 7.2 Run `flutter analyze` on `lib/performance/performance_heatmap.dart` — must report no issues.

## 8. Manual verification

- [ ] 8.1 Launch the app and open the performance page; confirm the grid renders with the current week on the right edge.
- [ ] 8.2 Verify Monday is the top row, Sunday the bottom row.
- [ ] 8.3 Confirm month labels appear at the correct column transitions for the visible window.
- [ ] 8.4 Confirm days after today (in the current week) render as blank placeholders, not zero-activity grey.
- [ ] 8.5 Sign in as a fresh user (or temporarily clear performance data) and confirm the empty grid still renders.
- [ ] 8.6 Confirm a known high-completion day (>10) shows the yellow outline.
