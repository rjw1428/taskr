## Context

Accomplishments live in `todos/{uid}/accomplishments`. The service currently exposes a single read path:

```dart
// lib/services/accomplishment.service.dart
var ref = _db.collection('todos').doc(user.uid).collection('accomplishments');
return ref.snapshots().map((list) {
  final accomp = list.docs.map(...).toList();
  accomp.sort((a, b) => b.date.compareTo(a.date));   // client-side ordering
  return accomp;
});
```

No `orderBy`, no `limit`, no `where`. Two callers consume it, and both over-fetch:

- `_AccomplishmentsSummary` (`performance_page.dart:563`) subscribes, then does `accomplishments.take(5)` at line 580. The "5" is display truncation, not a query bound — the full collection is downloaded on every Performance tab visit.
- `AccomplishmentDetailPage` (`accomplishment_detail_page.dart:16`) subscribes to the same full stream solely to `indexWhere((acc) => acc.id == accomplishment.id)`, so it can re-render on edit and pop itself on delete.

Layout constraint: the Performance tab is a `SingleChildScrollView` → `Column` (line 112), and the summary is a `SizedBox(height: 200)` wrapping a `ListView.builder` (lines 592–593) — a bounded inner scroll region nested inside the page scroll.

Relevant facts: `date` is written as `DateTime.now().toIso8601String()` (`accomplishment_form.dart:123`) and preserved verbatim on edit; ISO-8601 sorts lexicographically in chronological order. Nothing in `lib/` paginates today — a grep for `startAfter`/`limit(` finds only `limit(1)` existence checks and `limit(100)` in `notification.service.dart`. Firestore rules, indexes, and functions are deployed manually by the user, so any index requirement is a handoff cost, not an automatic step.

## Goals / Non-Goals

**Goals:**

- Make the full accomplishment log reachable and comfortable to scroll back through.
- Stop the Performance tab from downloading the entire collection to render five rows.
- Keep realtime semantics intact for everything on screen, including the detail view's delete-and-pop behavior.
- Avoid requiring a Firestore index deployment.

**Non-Goals:**

- Search, sort-by-difficulty, date-range filtering, export, or AI summarization of a range. The history page should not foreclose these, but none are built here.
- Promoting accomplishments to a bottom-nav destination. The user's framing was "useful sometimes as opposed to all the time," which argues for a drill-in, not a permanent tab.
- Any change to the data model, the create/edit form, or the Performance tab FAB.
- Offline//cache tuning beyond Firestore's defaults.

## Decisions

### Pagination via a growing limit, not cursor pages

Re-subscribe with a larger `limit` as the user scrolls, rather than accumulating `startAfterDocument(...).get()` pages into a local list.

*Why:* the entire loaded window stays a single live query, which preserves the realtime guarantees the specs require and which `AccomplishmentDetailPage` already depends on. It also fits the existing `StreamBuilder` + provider idiom with no new state-management machinery — the codebase has no pagination precedent to follow, so the cheaper pattern wins.

*Alternative — cursor pages:* reads each document exactly once (20/40/60 costs 60 reads vs. 120 for a growing limit), and is the textbook approach. Rejected because older pages become static snapshots: a deleted accomplishment would linger in the list, and we would be hand-rolling page state, in-flight flags, and end-of-collection detection. At realistic volumes (hundreds of accomplishments, one user) the read differential is negligible against the correctness and complexity win.

*Alternative — load everything at once:* this is the status quo, and it is exactly the cost being removed.

### Ordering moves into the query; the client sort is deleted

Add `.orderBy('date', descending: true)` and an optional `.limit(n)`. A limit is only meaningful against a defined order, so the two land together.

*Why no index deployment:* this is a single-field sort, covered by Firestore's automatic single-field indexes. No composite index, nothing for the user to deploy. Preserving this property is a design constraint — introducing any `where` clause alongside the sort (e.g. for filtering) would break it, which is part of why filtering is a non-goal here.

*Correctness:* server-side ordering on the ISO-8601 `date` string reproduces the existing client-side `b.date.compareTo(a.date)` exactly, so the sort is redundant once the query is ordered. Retaining it would silently mask an ordering regression, so it is removed rather than left as belt-and-braces.

### The detail view gets a document stream instead of scanning a collection

`AccomplishmentDetailPage` currently finds its accomplishment by scanning the full-collection stream. Once callers pass a limit, that approach is actively wrong: the page would either have to keep requesting the unbounded query (defeating the change) or risk its target falling outside the fetched window.

Give it a document-level stream keyed by id. Presence/absence of the document drives the existing "deleted → pop" path directly, which is more precise than `indexWhere(...) == -1` and removes the page's dependence on any list query's bounds.

*Alternative — pass the limit through from each caller:* leaves the page's correctness coupled to whatever window its opener happened to fetch. Rejected.

### A dedicated page, not a taller inline box

Infinite scroll cannot live in the existing summary. A `SizedBox(height: 200)` inner `ListView` nested in the page's `SingleChildScrollView` means an unbounded list inside a 200px porthole, competing for drag gestures and stranding the Records card below a list that never ends.

So: the summary stays exactly as it is (5 rows, fixed height) as the always-visible peek, and a new full-height page owns the unbounded list and the only scroll axis. This also satisfies the "sometimes, not all the time" constraint — the Performance tab pays no additional real estate.

Entry point: a trailing `See all` text button in a `Row` alongside the existing `'Latest accomplishments'` header, matching the header-with-trailing-control pattern the Daily score card already uses (`performance_page.dart:124`).

### Page size 20; summary stays 5

20 fills a phone screen with room to scroll before the first extension, so the loading indicator is rarely the first thing the user sees. The summary's 5 becomes a real query bound (`limit: 5`) rather than a `.take(5)`.

### Month grouping computed client-side

Headings come from parsing `date` on the loaded entries. There is no month field to group on server-side and adding one would be a data model change. Parsing a few hundred ISO strings is not a measurable cost, and grouping only ever runs over already-loaded entries.

## Risks / Trade-offs

- **Re-subscription cost grows quadratically** (20 → 40 → 60 re-reads the window each time) → Accepted deliberately; see the pagination decision. If a user ever accumulates thousands of accomplishments, revisit with cursor pages, keeping the newest page live and older pages static.
- **Re-subscribing can flicker or reset scroll position** as `StreamBuilder` rebuilds with a new stream → Hold the stream in state and only swap it when the limit actually changes, so unrelated rebuilds do not resubscribe. The spec requires scroll position to survive an appended page; this is the main thing to verify by hand.
- **A scroll listener can fire repeatedly near the threshold and request several pages at once** → Guard with an in-flight flag and a has-more flag; stop extending once a returned page is shorter than the requested limit.
- **The detail page rewrite touches working delete-and-pop behavior** → It is the subtlest part of this change. The existing `addPostFrameCallback` pop guarded by `Navigator.canPop` should be preserved as-is; only the source of "does this still exist" changes.
- **Bounding the summary is a behavioral narrowing** → Any consumer implicitly relying on that stream carrying the full collection breaks. The detail page is the one known case and is addressed directly; the grep for `getAccomplishments()` callers should be re-run at implementation time to confirm there are no others.
- **`date` is caller-supplied and unvalidated** → A malformed value would sort oddly and could throw in `DateTime.parse` during grouping. This is a pre-existing exposure (the summary already calls `DateTime.parse` at line 599), not one this change introduces, but the grouping code should not be the thing that turns it into a crash.

## Migration Plan

No data migration, no schema change, no index deployment, no rules change — nothing for the user to deploy. The change is entirely client-side and ships in one commit.

Sequencing that keeps the tree working at each step: service gains the optional parameters (existing unbounded callers keep working unchanged) → detail page moves to a document stream → summary adopts `limit: 5` → new history page → `See all` affordance wires them together.

Rollback is reverting the commit; because nothing is written differently, no data is left in a mixed state.

## Open Questions

- Should the `See all` affordance be suppressed when the user has 5 or fewer accomplishments, or always shown for a stable layout? Leaning always-shown.
- Should month headings for the current year omit the year (`August` vs `August 2026`)? Cosmetic; defer to implementation.
- Does an accomplishment created while the history page is open need to scroll itself into view, or merely appear at the top? The spec only requires that it appear.
