## 1. Service query: ordering and bounds

- [x] 1.1 In `lib/services/accomplishment.service.dart`, convert `final FirebaseFirestore _db = FirebaseFirestore.instance` to a `late` field with an `@visibleForTesting` setter, matching the pattern in `goal.service.dart` / `habit.service.dart` (do not leave it eager — an eager field cannot be injected in tests)
- [x] 1.2 Add `.orderBy('date', descending: true)` to the query in `getAccomplishments()`
- [x] 1.3 Add an optional `int? limit` parameter to `getAccomplishments()`, applying `.limit(limit)` only when non-null
- [x] 1.4 Delete the now-redundant client-side `accomp.sort((a, b) => b.date.compareTo(a.date))`
- [x] 1.5 Add `Stream<Accomplishment?> getAccomplishment(String id)` returning a single-document snapshot stream, emitting `null` when the document does not exist
- [x] 1.6 Thread the optional `limit` through `AccomplishmentProvider.getAccomplishments()` and expose `getAccomplishment(id)` in `lib/services/accomplishment.provider.dart`
- [x] 1.7 Confirm no Firestore index is required — verify the query is a single-field `orderBy` with no `where` clause, so automatic single-field indexes cover it and nothing needs deploying

## 2. Detail page: track a document, not a collection

- [x] 2.1 In `lib/accomplishments/accomplishment_detail_page.dart`, replace the full-collection `StreamBuilder` + `indexWhere` lookup with a `StreamBuilder<Accomplishment?>` over `getAccomplishment(id)`
- [x] 2.2 Drive the deleted-and-pop path off a `null` document instead of `indexWhere(...) == -1`, preserving the existing `addPostFrameCallback` + `Navigator.canPop` guard exactly as written
- [x] 2.3 Verify by hand: open a detail page, edit it, confirm values update in place; delete it, confirm the page pops back to its opener

## 3. Performance tab summary: fetch only what it renders

- [x] 3.1 In `lib/performance/performance_page.dart`, change `_AccomplishmentsSummary` to call `getAccomplishments(limit: 5)` and remove the `.take(5)` at line 580
- [x] 3.2 Confirm the rendered rows are visually unchanged — same score badge, title, `MM/DD` date, ordering, fixed 200px height
- [x] 3.3 Re-run a grep for `getAccomplishments(` callers to confirm no other consumer relied on the stream carrying the full collection

## 4. History page

- [x] 4.1 Create `lib/accomplishments/accomplishment_list.dart` with a `Scaffold` + `AppBar` titled "Accomplishments", the list as the page's only scrolling region (no nested fixed-height box)
- [x] 4.2 Hold the current limit in state (initial 20) and hold the stream itself in state, swapping it only when the limit actually changes so unrelated rebuilds do not resubscribe
- [x] 4.3 Attach a `ScrollController` that extends the limit by one page when the user scrolls near the end of the loaded entries
- [x] 4.4 Guard extension with an in-flight flag and a has-more flag; stop extending once a returned page is shorter than the requested limit, and stop showing the loading indicator at that point
- [x] 4.5 Group loaded entries under month headings derived from parsing `date`, newest-first, tolerating an unparseable `date` without crashing the list
- [x] 4.6 Render each entry with the same score badge / title / date treatment as the Performance summary, tapping through to `AccomplishmentDetailPage`
- [x] 4.7 Show an `EmptyState` when the user has no accomplishments, following the pattern used in `goal_list.dart` / `people_list.dart`
- [x] 4.8 Show a loading indicator while an additional page is in flight

## 5. Entry point from the Performance tab

- [x] 5.1 Wrap the `'Latest accomplishments'` header (`performance_page.dart:222`) in a `Row` with a trailing `See all` text button, matching the header-with-trailing-control pattern of the Daily score card at line 124
- [x] 5.2 Push `AccomplishmentListPage` on tap
- [x] 5.3 Confirm the rest of the Performance tab — average header, charts, heatmap, pushed chart, Records card — is unchanged in position and behavior

## 6. Tests

- [x] 6.1 Add `test/accomplishment_service_test.dart` using `fake_cloud_firestore`, injecting the fake via the `@visibleForTesting` db setter
- [x] 6.2 Test: entries arrive ordered newest-first without any client-side sort
- [x] 6.3 Test: a request with `limit: N` yields exactly the N most recent entries when more exist
- [x] 6.4 Test: a request without a limit yields all entries, ordered newest-first
- [x] 6.5 Test: `getAccomplishment(id)` emits the document, emits updated values on edit, and emits `null` after deletion
- [x] 6.6 Extract month-grouping into a pure function and unit-test it directly (grouping, ordering of groups, unparseable `date` handling) rather than testing it through a widget
- [x] 6.7 Run `flutter test` and confirm the suite passes

## 7. Manual verification

- [x] 7.1 With more than 20 accomplishments, scroll the history page and confirm additional pages load and older months become reachable
- [x] 7.2 Confirm scroll position is preserved when a page is appended — the content being read does not jump
- [x] 7.3 Confirm scrolling to the true end stops requesting pages and leaves no perpetual spinner
- [x] 7.4 With fewer than 20 accomplishments, confirm all are shown and no extra page is requested
- [x] 7.5 With the history page open, create an accomplishment and confirm it appears at the top under the right month heading; edit one and confirm it updates in place; delete one and confirm it disappears
