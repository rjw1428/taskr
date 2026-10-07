# Pin Work Actions — Design

## Context

The Work tab (`lib/work/`) streams `todos/{uid}/work` into a reorderable list of priorities (`WorkItem`), each card showing its open next actions (`NextAction` maps embedded in the document). All next-action mutations flow through `WorkActions` → `WorkLogic` (pure list transforms) → `WorkService.setNextActions` (single-field document update). Colors come from the `AppTokens` theme extension in `lib/shared/design/tokens.dart`, which already carries per-brightness palettes (`PriorityColor` with fill/border/ink/accent). Firebase rules and indexes are deployed manually by the user, so designs that need neither are preferred.

## Goals / Non-Goals

**Goals:**
- Pin any open next action from any priority; pins persist and sync via the existing document stream.
- A pinned-actions list at the top of the Work page, visually distinct via a dedicated pinned color, naming each action's source priority.
- Completing a pinned action from either list sets `completedAt` on the one embedded action; both lists update from the same stream emission. Undo restores it to both.
- Zero Firestore rules/index changes; old documents load unchanged.

**Non-Goals:**
- No pinning of whole work items (priorities) — only next actions.
- No manual reordering of the pinned list (ordered by pin time).
- No pins for tasks/backlog items; this is Work-page-only.
- No change to Markdown export, timeline, or archive behavior.

## Decisions

### 1. Pin state lives on the embedded next action as `pinnedAt` (nullable epoch millis)

`NextAction` gains `pinnedAt` (`int?`, absent/null = unpinned), written through the existing `setNextActions` path.

- **Why not a separate pins document/collection?** It would need its own stream, security-rule addition (user deploys rules manually), and could orphan pins when actions complete or items are deleted. Embedding keeps one source of truth, one stream, and atomic updates per item.
- **Why a timestamp instead of a bool?** Null-vs-set matches the existing `completedAt`/`waitingOn` idiom, and the timestamp doubles as the pinned list's sort key (oldest pin first — stable, no reorder churn).
- `models.g.dart` regenerates via `build_runner`; no `defaultValue` so a missing field parses as null.

### 2. Completion does not touch `pinnedAt`; the pinned list derives from open ∧ pinned

The pinned list renders `action.isOpen && action.pinnedAt != null`. Completing sets only `completedAt` (existing `WorkLogic.completeNextAction`, unchanged), which removes the row from both lists. Undo clears `completedAt` and the action reappears in both lists, pin intact.

- **Why not clear the pin on complete?** It complicates undo (the old `pinnedAt` would have to be remembered by the snackbar closure) for no user-visible gain — a retained `pinnedAt` on a completed action is inert metadata. Deriving visibility keeps the complete/undo code paths byte-for-byte what they are today.
- Alternative rejected: eager-clear with undo-re-pin — more code, same visible behavior except a lost pin after undo, which would read as a bug.

### 3. The pinned section is derived from the existing stream, rendered above the board

No second query. `WorkPage` already holds `List<WorkItem>`; a pure helper `WorkLogic.pinnedActions(items)` returns `(WorkItem, NextAction)` pairs sorted by `pinnedAt` ascending. A new widget `lib/work/pinned_actions_section.dart` renders them between the header row and the `ReorderableListView`, inside the existing `Column`; it renders `SizedBox.shrink()` when empty so the board is untouched when nothing is pinned.

- Each pinned row: checkbox (completes via the same `WorkActions.complete`), action text, and the source priority's title as a secondary line; tapping the row can jump/scroll is **not** included (non-goal creep) — tapping edits the action like on the card.
- Waiting actions can be pinned; in the pinned list they keep the hourglass-instead-of-checkbox treatment so a waiting step still can't be ticked accidentally.
- The pinned section sits outside the `ReorderableListView` so drag-reorder of priorities is unaffected.

### 4. Pin toggle is a thumbtack affordance on each open action row

`NextActionRow` gains a `pinned` flag and `onTogglePin` callback: a small thumbtack icon button at the row's trailing edge (next to the waiting overflow when present). Pinned rows show the thumbtack filled in the pinned accent color; unpinned rows show it faint. The pinned list's rows reuse the same toggle to unpin without completing.

- **Why not pin via a long-press or overflow menu only?** Discoverability — the feature's whole point is fast triage; one tap to pin/unpin. The icon-button pattern already exists in these rows (waiting overflow).
- `WorkActions.togglePin(itemId, action)` uses the existing `_mutateActions` read-latest-then-write pattern with a new pure `WorkLogic.setPinned(actions, id, pinnedAt)`.

### 5. New `pinned` token on `AppTokens`, brand aqua, defined for both brightnesses

Add `PriorityColor pinned` to `AppTokens` (fill/border/ink/accent), built on the existing aqua/teal brand accent (`Brand.accentDark`/`Brand.accentLight`) — pinned surfaces read as the app's own accent color while staying visually distinct from the semantic red/amber/green, the info neutral, and the gold goal token. Used for: pinned-section card backgrounds/borders, the filled thumbtack, and a pinned tint on the action row within its source card.

- **Why a full `PriorityColor` instead of one Color?** The pinned list draws cards (needs fill/border/ink), matching how every other colored surface in the app is specified; `lerp`/`copyWith` extend mechanically.

### 6. Scope of pin visibility: active board only

The pinned list derives from `streamActive()` only. Archiving an item removes its actions from the pinned list automatically (the item leaves the stream); restoring brings still-pinned open actions back. The detail page and archive page need no pin UI beyond the row toggle the shared `NextActionRow` already carries (archive page renders read-only cards — unchanged).

## Risks / Trade-offs

- [Whole-array write race: two devices mutating `nextActions` concurrently last-write-wins] → Pre-existing pattern (`_mutateActions` re-reads before writing); pinning adds no new write shape, so the risk is unchanged, accepted.
- [Pinned list pushes the board down on small screens when many actions are pinned] → The section is a plain Column sized to content inside the page's scroll context; spec caps expectations at "list renders all pinned actions", and pin friction (manual, per-action) naturally bounds count. If it becomes a problem, a follow-up can collapse the section.
- [`models.g.dart` regeneration touches generated code] → Standard `dart run build_runner build` step; field is additive and nullable, so round-tripping old documents is lossless.
- [Thumbtack adds a third interactive element to dense rows] → Keep it 28×28 like the existing waiting overflow, trailing-aligned; widget tests assert both checkbox and pin remain hittable.

## Migration Plan

None needed. The field is additive and nullable; existing documents read as unpinned. No rules, index, or function changes for the user to deploy. Rollback = revert the app code; stray `pinnedAt` fields in documents are ignored by old models (`json_serializable` drops unknown keys on read paths used here).

## Open Questions

None — behavior questions (undo semantics, waiting-action pinning, ordering) are decided above.
