## Why

The Performance tab shows only the 5 most recent accomplishments, and there is no way to reach the sixth. Accomplishments are a durable log the user builds over time — a record of wins worth revisiting — but everything older than the last handful is currently unreachable in the UI despite being stored.

The same code path is also the app's largest unnecessary read. `AccomplishmentService.getAccomplishments()` issues an unbounded `snapshots()` on the whole subcollection and the caller discards all but 5 entries client-side, so every visit to the most-frequented analytics tab downloads the user's entire accomplishment history. That cost grows without bound and never gets cheaper to fix.

## What Changes

- Add a dedicated accomplishment history page listing the full log, newest first, grouped by month, with incremental ("infinite scroll") loading as the user scrolls back through time.
- Add a way to reach it from the existing "Latest accomplishments" section on the Performance tab.
- Move ordering and limiting into the Firestore query so callers fetch only what they render. The Performance summary requests 5 instead of pulling the whole collection and truncating in Dart.
- Preserve realtime behavior for everything currently loaded: edits and deletions to any visible accomplishment continue to propagate, including the existing behavior where `AccomplishmentDetailPage` auto-pops when its accomplishment is deleted.
- No changes to the accomplishment data model, the create/edit form, or the FAB.

Not in scope (deliberately deferred): search by title, sort by difficulty score, date-range filtering, and any export or summarization of a date range. The history page should leave room for these without committing to them now.

**BREAKING**: none. `getAccomplishments()` gains an optional parameter and a defined sort order; existing callers keep working.

## Capabilities

### New Capabilities

- `accomplishment-history`: Browsing the full accomplishment log beyond the recent few — a dedicated history view reached from the Performance tab, ordered newest-first, grouped by month, loading incrementally as the user scrolls, and staying live for loaded entries. Also covers the query-level ordering and limiting contract that lets callers fetch only the entries they display.

### Modified Capabilities

<!-- None. `app-navigation-shell` specs the per-tab FAB create action, which is unchanged.
     `performance-records` specs the Records card, which is untouched.
     No existing spec covers the accomplishments list. -->

## Impact

- **Code modified:**
  - `lib/services/accomplishment.service.dart` — `getAccomplishments()` gains server-side `orderBy` on `date` (descending) and an optional result limit; the client-side `accomp.sort(...)` becomes redundant and is removed.
  - `lib/services/accomplishment.provider.dart` — pass the limit through to the service.
  - `lib/performance/performance_page.dart` — `_AccomplishmentsSummary` requests a bounded query instead of `.take(5)` on an unbounded one; the section header gains an affordance to open the history page.

- **Code added:**
  - `lib/accomplishments/accomplishment_list.dart` — the history page.

- **Data / infrastructure:**
  - No schema change. `date` is stored as an ISO-8601 string, which sorts lexicographically in chronological order, so server-side ordering is consistent with the current client-side sort.
  - **No Firestore index deployment required.** Ordering is a single-field sort on `date`, covered by Firestore's automatic single-field indexes; no composite index is involved.

- **Behavioral risk:** the Performance tab's summary moves from "all documents, locally truncated" to "5 documents from the server". Any consumer that implicitly relied on the stream carrying the full collection must be re-checked — `AccomplishmentDetailPage` currently locates its accomplishment by scanning that same stream and is the known case.
