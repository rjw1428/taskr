## Context

The performance page (`lib/performance/performance_page.dart`) already pulls a `streamPerformance(userId, 7daysAgo)` for the line chart and `streamPerformanceForMonth` (via the heatmap) for the contributions grid. Performance documents live at `todos/{uid}/performance/{YYYY-MM-DD}` with a `completed: { ALL: int, ...tags }` field. The `streamPerformanceForMonth` method is range-based despite its name; we can reuse it for any window.

This change adds one new piece of UI — a tappable header at the top of the page that shows a rolling average and cycles through 4 fixed windows on tap.

## Goals / Non-Goals

**Goals:**
- One always-visible top-line metric on the performance page.
- Tap cycles through 4 windows: 7d, 30d, 90d, 365d.
- Average = sum of `completed.ALL` across window ÷ calendar days in window (zero-activity days included).
- Year window clamps to the user's actual data span if shorter than 365 days.
- Two-decimal formatting throughout.

**Non-Goals:**
- No new Firestore documents, indexes, or cloud functions.
- No persistence of the selected window across page mounts — resets to 7d each time. Persistence is straightforward to add later if asked.
- No animation between window changes beyond Flutter's default state-rebuild.
- No multi-user comparisons or trend indicators (up/down arrows).

## Decisions

### Decision: One stream sized to the largest window (365 days)

Rather than running four parallel queries or re-subscribing on each tap, the header subscribes to a single `streamPerformanceForMonth` call covering `[today - 365 days, today]`. The four averages are derived client-side from the same in-memory list by filtering on date. This:
- Eliminates re-subscription churn on tap (Firestore stays steady; only the displayed number changes).
- Reuses the existing service signature.
- Costs at most ~365 doc reads on initial subscription, which is well within sane bounds (~$0.0002 per render).

**Alternative considered:** subscribe to a fresh range on each tap. Rejected because the latency on tap would be noticeable and the read cost ends up similar over a session.

**Alternative considered:** lift the existing 13-week heatmap stream and share it. Rejected because the year window would still need a separate, wider subscription — simpler to give the header its own stream that covers all four windows.

### Decision: Year window denominator = `min(365, daysSinceOldestDoc)`

The user's intent is "average over the year, or the longest timeframe if less." Implementation:
- Find the oldest document in the stream's result set.
- `daysSinceOldest = floor((today - oldestDate) / 1 day) + 1`.
- `windowDays = min(365, daysSinceOldest)`.
- Sum points over `[today - windowDays + 1, today]`.

For windows shorter than a year (7d, 30d, 90d) we don't clamp — they show whatever data exists, with absent days counted as zero. This is consistent with "averaging across calendar days" being the user's mental model.

### Decision: Zero-activity days count toward the denominator

`average = totalPoints / windowDays`, where `windowDays` is a calendar-day count, not a count-of-days-with-data. A user who completed tasks 3 of the last 7 days reads "lower average" than someone who did the same volume across all 7 — which is the honest signal.

### Decision: Window state is local to the header widget

The selected window is a `StatefulWidget` field. No need for `Provider` or app-wide state — only the header consumes it.

### Decision: Label vocabulary

- 7d → "Last 7 days"
- 30d → "Last month"
- 90d → "Last 3 months"
- 365d → "Last year"

When the year window is clamped (`daysSinceOldest < 365`), the label stays "Last year" rather than displaying the clamped count — the numeric average is what matters and exposing internals would be noisy.

### Decision: Two-decimal formatting via `toStringAsFixed(2)`

Dart's built-in `num.toStringAsFixed(2)` does exactly what we want, including the integer and zero cases. No need for `intl`'s `NumberFormat`.

## Risks / Trade-offs

- **Initial stream cost grows with window size.** ~365 reads per page mount for the year window vs. ~91 for the heatmap. Negligible at current scale; revisit if performance page mounts get hot.
- **Tap-to-cycle is non-obvious.** A user may not realize the header is tappable. Mitigation: include a visible affordance (small swap-icon or hint subtitle). If discoverability becomes a problem, a segmented control could replace cycling — but cycling keeps the header compact, which matches the "glanceable" intent.
- **No persistence across page mounts.** Re-entering the page resets to 7d. Acceptable for v1; persistence (e.g., `SharedPreferences`) is a small follow-up if requested.
