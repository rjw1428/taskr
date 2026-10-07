# Pin Work Actions — Tasks

## 1. Data model

- [x] 1.1 Add nullable `pinnedAt` (`int?`) to `NextAction` in `lib/services/models.dart`: field, constructor param, `isPinned` getter, and `copyWith` support using the existing `_unset` sentinel so null can be written explicitly
- [x] 1.2 Regenerate `lib/services/models.g.dart` with `dart run build_runner build --delete-conflicting-outputs`
- [x] 1.3 Extend `test/work_models_test.dart`: `pinnedAt` round-trips through JSON, missing field parses as null/unpinned, `copyWith` can set and clear it, and unrelated `copyWith` calls preserve it

## 2. Pure logic

- [x] 2.1 Add `WorkLogic.setPinned(List<NextAction> actions, String id, int? pinnedAt)` returning a new list with only that action's `pinnedAt` changed
- [x] 2.2 Add `WorkLogic.pinnedActions(List<WorkItem> items)` returning `(WorkItem, NextAction)` pairs for every open pinned action across items, sorted by ascending `pinnedAt`
- [x] 2.3 Extend `test/work_logic_test.dart`: pin/unpin targets only the matching action; derivation excludes completed and unpinned actions, spans multiple items, and orders by pin time; complete/undo leave `pinnedAt` untouched

## 3. Mutations

- [x] 3.1 Add `WorkActions.togglePin(String itemId, NextAction action)` using `_mutateActions` + `WorkLogic.setPinned` (pin stamps `service.now()`, unpin writes null), wrapped in `guard`
- [x] 3.2 Extend `test/work_service_test.dart` (or actions coverage therein): togglePin persists `pinnedAt` via `setNextActions`, re-reads the latest item before writing, and leaves other actions and fields unchanged

## 4. Design token

- [x] 4.1 Add a `pinned` `PriorityColor` (fill/border/ink/accent) to `AppTokens` in `lib/shared/design/tokens.dart` — brand aqua family (built on `Brand.accentDark`/`Brand.accentLight`), tuned per brightness, distinct from priority/goal hues; wire through constructor, `dark`/`light` presets, `copyWith`, and `lerp`
- [x] 4.2 Extend `test/design_components_test.dart` (or tokens coverage): both brightnesses define the pinned token and `lerp` interpolates it

## 5. Row toggle UI

- [x] 5.1 Add `pinned` flag and `onTogglePin` callback to `NextActionRow` (`lib/work/next_action_row.dart`): trailing 28×28 thumbtack icon button, filled with the pinned accent when pinned, faint when not, with `Key('pin-<action id>')` and a tooltip
- [x] 5.2 Pass pin state and `WorkActions.togglePin` through from `WorkItemCard` (and `work_detail_page.dart` if it renders rows) so every open action row on an active item can toggle
- [x] 5.3 Widget tests: tapping the thumbtack pins/unpins, pinned row shows the filled accent glyph, checkbox and pin remain individually hittable, waiting rows keep hourglass + overflow alongside the pin toggle

## 6. Pinned section

- [x] 6.1 Create `lib/work/pinned_actions_section.dart`: renders `WorkLogic.pinnedActions` pairs as cards styled with the pinned token, each row showing action text, source priority title as a secondary line, checkbox (or hourglass treatment for waiting actions, completing via overflow), pin toggle to unpin, and tap-to-edit matching card behavior; returns `SizedBox.shrink()` when empty
- [x] 6.2 Mount the section in `lib/work/work_page.dart` between the header row and the `ReorderableListView`, wiring `WorkActions.complete`, `togglePin`, and `editNextAction` with the owning item's id
- [x] 6.3 Extend `test/work_page_test.dart`: section hidden with no pins; shows actions from multiple priorities ordered by pin time with source titles; checking in the section completes the embedded action and removes it from both the section and the card; Undo restores it to both still pinned; unpinning from the section leaves the action open on its card; archiving an item removes its actions from the section

## 7. Verify

- [x] 7.1 Run `flutter analyze` and the full `flutter test` suite; confirm coverage of the new code meets the project's 90% goal
- [x] 7.2 Run the app and smoke-test: pin from two priorities, check one from the pinned list, undo, unpin the other, archive a priority with a pin — in both light and dark themes
