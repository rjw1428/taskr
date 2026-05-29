## 1. Header widget skeleton

- [x] 1.1 Create `lib/performance/performance_average_header.dart` with a `StatefulWidget` taking `userId`.
- [x] 1.2 Add an enum or constant list of windows: `[7, 30, 90, 365]` with paired labels `["Last 7 days", "Last month", "Last 3 months", "Last year"]`.
- [x] 1.3 Store the selected window index as state, default 0 (7 days).

## 2. Data subscription

- [x] 2.1 Inside `build`, compute `streamStart = today - 365 days` and `streamEnd = today` (date-only, local).
- [x] 2.2 Wrap a `StreamBuilder` around `PerformanceService().streamPerformanceForMonth(userId, streamStart, streamEnd)`.
- [x] 2.3 In the builder, normalize results into `Map<DateTime (date-only), int>` keyed by the document's `date` field, using `completed.ALL` (default 0).

## 3. Average computation

- [x] 3.1 Implement `_averageFor(windowDays, scoresByDay, today)` that returns a `double`.
- [x] 3.2 For windows other than 365: `windowStart = today - (windowDays - 1) days`; sum scores in `[windowStart, today]`; divide by `windowDays`.
- [x] 3.3 For the 365 window: compute `daysSinceOldest` from the keys in `scoresByDay` (or, if empty, 1); set `effectiveDays = min(365, daysSinceOldest)`; sum scores over `[today - effectiveDays + 1, today]`; divide by `effectiveDays`.
- [x] 3.4 Guard divide-by-zero: if there is no data at all, return `0.0`.

## 4. Rendering

- [x] 4.1 Render the average via `value.toStringAsFixed(2)` in a large text style.
- [x] 4.2 Render the window label below or beside the number in a smaller, subtler style.
- [x] 4.3 Wrap the whole header in an `InkWell` (or `GestureDetector` with `HitTestBehavior.opaque`) so taps anywhere on the surface advance the window.
- [x] 4.4 Add a small affordance hinting at the tap behavior — e.g., a trailing `Icons.swap_horiz` or `Icons.touch_app` next to the label.

## 5. Tap behavior

- [x] 5.1 On tap, call `setState` to advance the window index: `(index + 1) % windows.length`.
- [x] 5.2 Confirm rebuild keeps the same StreamBuilder subscription (no re-query on tap).

## 6. Page integration

- [x] 6.1 In `lib/performance/performance_page.dart`, import the new widget.
- [x] 6.2 Add `PerformanceAverageHeader(userId: user.uid)` as the first child of the `SingleChildScrollView`'s `Column`, above the `PerformanceHeatmap`.
- [x] 6.3 Insert a `SizedBox(height: 16)` between the header and the heatmap.

## 7. Cleanup

- [x] 7.1 Run `flutter analyze lib/performance/` — must report no issues.

## 8. Manual verification

- [ ] 8.1 Launch the app and open the performance page; confirm the header reads "Last 7 days" with a 2-decimal value.
- [ ] 8.2 Tap the header; confirm it advances to "Last month" with a recomputed average.
- [ ] 8.3 Continue tapping; confirm "Last 3 months" and "Last year" appear in order, then wrap back to "Last 7 days".
- [ ] 8.4 Verify the integer/zero cases display as "X.00" rather than "X" or "X.0".
- [ ] 8.5 Sign in as a recent user (or one with < 365 days of data) and confirm the "Last year" average is based on whatever data exists, not divided by 365.
