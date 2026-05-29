## Context

The current `PerformanceHeatmap` widget at `lib/performance/performance_heatmap.dart` renders one calendar month at a time. Layout is row-major: rows are weeks of the month (max 6), columns are weekdays Mon–Sun, and each cell shows the day-of-month number tinted by completion count. The data source is `PerformanceService.streamPerformanceForMonth(userId, startDate, endDate)`, which is already range-based despite its name — it accepts any two dates and returns a list of daily performance documents from Firestore.

The current widget has a useful color ramp and a Firestore stream subscription that already works. What it lacks is continuity: at month rollover, the previous month vanishes; week-over-week patterns are split across rows; and there's no way to see a sustained streak.

The redesign is purely visual + layout. No service, model, schema, security rule, or cloud function changes are required.

## Goals / Non-Goals

**Goals:**
- Replace the single-month grid with a multi-month GitHub-style contributions grid (columns = weeks oldest→newest, rows = weekdays).
- Reuse `PerformanceService.streamPerformanceForMonth` with a wider range.
- Keep the existing green color ramp and bucket thresholds so the change reads as a layout swap, not a redesign.
- Render a full rectangular grid even for new users (empty cells, not a "no data" message).

**Non-Goals:**
- No changes to the data model, Firestore schema, or service signatures.
- No interactivity (tooltips, day tap, range picker) in this change — those can come later if desired.
- No theming overhaul; only the heatmap widget changes. The rest of the performance page (line chart, accomplishments list) is untouched.

## Decisions

### Decision: Column-major layout via `Row` of `Column`s (not `GridView`)

A `GridView` with `crossAxisCount: 7` would force row-major item order, which fights the column-major mental model and complicates the "empty leading cells" math for the oldest week. Instead, layout will be a `Row` of `N` `Column`s, each containing 7 cell widgets. This makes each "week column" a coherent unit, simplifies month-label alignment (one label slot per column), and matches how the user perceives the grid.

**Alternative considered:** keep `GridView` and remap indices. Rejected because the index math is error-prone and the empty-cell logic for the oldest visible week (which may start mid-week) and the current week (which may end mid-week) is awkward to express cell-by-cell.

### Decision: Window of 13 weeks (~3 months)

`13 × 7 = 91` days ≈ 3 calendar months and produces a roughly square grid given typical cell sizes. This matches the visible information density of the prior month-grid (28–31 cells) at ~3× the breadth, without scrolling. A wider window (say 26 weeks for half a year) is appealing but cells become small on phone screens; 13 weeks is a reasonable phone-first default. The number is encoded as a constant in the widget so it can be tweaked.

### Decision: Range computation

The visible window is `[mondayOfOldestWeek, sundayOfCurrentWeek]` where `mondayOfOldestWeek = monday(today) - (weekCount - 1) weeks`. The widget computes this once per build (it's pure given `DateTime.now()`) and passes both ends to the existing service stream.

### Decision: Future/leading cells use transparent placeholders

The oldest week may start before the window opens (no leading-cell case, since we anchor on Monday) — but the *current* week will routinely end mid-week. Days after today in the current week render as `SizedBox` placeholders (same size, transparent) so the grid stays rectangular without misrepresenting future days as zero-activity.

### Decision: Empty-state shows the grid, not a message

The prior implementation rendered "No performance data for this month" when the snapshot was empty. With the new wider window this would almost always trigger for new users. The new behavior renders the full empty-bucket grid (light grey) so the page has a stable shape; the user can already tell from the absence of color that nothing has been completed yet.

### Decision: Reuse existing color ramp

Keep the same `Colors.grey[200] → green[100] → green[300] → green[500] → green[700]` ramp and thresholds (1, 2, 5, 8). Familiar to anyone who has seen the current heatmap; matches GitHub's "fewer → more" intensity convention. The yellow "outstanding day" border (>10 completed) carries over.

### Decision: Month labels via prefix-scan

Walk columns left→right and emit a month label above column `i` when `month(monday(col_i)) != month(monday(col_{i-1}))`. Always label the first column. This avoids overlapping labels in narrow grids.

## Risks / Trade-offs

- **Cell size on small screens:** 13 columns × 7 rows on a phone width gives narrow cells. Acceptable for visual scanning but no longer fits a 2-digit day-of-month number. Resolved by dropping the day-of-month text entirely (it's redundant with the column position once month labels are in).
- **Firestore read volume:** widening from ~30 to ~91 days roughly triples the read cost per heatmap render. Reads are still per-user-per-day documents and the stream is subscribed only on the performance page, so the impact is small.
- **Loss of "which day was that?" precision:** without day numbers, a user can no longer point at a cell and say "that was the 14th." Mitigated by month labels and weekday rows; full precision can return as a tap-tooltip if requested later.
