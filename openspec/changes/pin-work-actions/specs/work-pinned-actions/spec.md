## ADDED Requirements

### Requirement: Pin and unpin next actions
The system SHALL let the user pin and unpin any open next action on any active work priority via a thumbtack toggle on the action's row, persisting pin state as a nullable `pinnedAt` timestamp (epoch milliseconds) on the next action map. Pinning SHALL write through the existing next-action update path and SHALL NOT modify any other field of the action or item besides `lastUpdated`.

#### Scenario: Pin an action
- **WHEN** the user taps the pin toggle on an open, unpinned next action
- **THEN** that action's `pinnedAt` SHALL be set to now and the action SHALL appear in the pinned list

#### Scenario: Unpin an action
- **WHEN** the user taps the pin toggle on a pinned action (from the pinned list or from its priority card)
- **THEN** that action's `pinnedAt` SHALL be cleared to null and the action SHALL leave the pinned list, remaining open on its priority card

#### Scenario: Waiting actions can be pinned
- **WHEN** the user pins a next action that has a non-null `waitingOn`
- **THEN** it SHALL be pinned like any other action and keep its waiting treatment everywhere it renders

#### Scenario: Missing field reads as unpinned
- **WHEN** a stored next action map lacks the `pinnedAt` field
- **THEN** the model SHALL load the action as unpinned instead of failing

### Requirement: Pinned list at the top of the Work page
The system SHALL render a pinned-actions section at the top of the Work page, above the priority list, containing every next action across all active priorities that is both open (`completedAt` null) and pinned (`pinnedAt` non-null), ordered by ascending `pinnedAt`. The section SHALL be derived from the same live stream as the board and SHALL NOT issue a separate query.

#### Scenario: Pinned actions from multiple priorities
- **WHEN** priority A has one pinned open action and priority B has two
- **THEN** the pinned section SHALL list all three, ordered by when each was pinned, oldest first

#### Scenario: Section hidden when empty
- **WHEN** no open action on any active priority is pinned
- **THEN** the Work page SHALL render no pinned section (no header, card, or empty placeholder)

#### Scenario: Pins sync across devices
- **WHEN** an action is pinned on one device
- **THEN** another device streaming the same collection SHALL show it in the pinned list without a restart

#### Scenario: Archiving removes from pinned list
- **WHEN** a priority with a pinned open action is archived
- **THEN** the pinned list SHALL no longer show that action
- **AND** restoring the priority SHALL return the still-pinned open action to the pinned list

### Requirement: Pinned rows identify their source priority
Each row in the pinned section SHALL show the action's text and the title of the work priority it belongs to.

#### Scenario: Source title shown
- **WHEN** the action "Draft the RFC" on priority "Migrate billing service" is pinned
- **THEN** its pinned row SHALL show "Draft the RFC" with "Migrate billing service" as a secondary line

### Requirement: Pinned styling uses a dedicated color
The system SHALL style the pinned section's cards with a dedicated pinned color token defined for both light and dark themes, visually distinct from the priority (high/medium/low/info) palettes, and SHALL render the pin toggle filled in the pinned accent color on pinned rows and faint on unpinned rows, including on the source priority's card.

#### Scenario: Pinned section color
- **WHEN** the pinned section renders
- **THEN** its cards SHALL use the pinned token's fill, border, and ink rather than the standard card surface

#### Scenario: Pinned action highlighted on its source card
- **WHEN** a pinned open action renders on its priority card
- **THEN** its row SHALL show the filled pinned-accent thumbtack, distinguishing it from unpinned rows

### Requirement: Completing from the pinned list completes everywhere
Checking an action in the pinned list SHALL perform the same completion as checking it on its priority card: `completedAt` set on the embedded action in its work item, the row removed from both the pinned list and the card, and the standard completion snackbar with Undo shown. Completion SHALL NOT modify `pinnedAt`; removal from the pinned list follows from the action no longer being open.

#### Scenario: Check in pinned list
- **WHEN** the user checks a pinned action in the pinned list
- **THEN** that action's `completedAt` SHALL be set to now on its work item
- **AND** the action SHALL disappear from both the pinned list and its priority card
- **AND** a snackbar with Undo SHALL appear

#### Scenario: Check on the source card
- **WHEN** the user checks a pinned action on its priority card
- **THEN** the action SHALL also disappear from the pinned list

#### Scenario: Undo restores both lists
- **WHEN** the user taps Undo after completing a pinned action
- **THEN** `completedAt` SHALL be cleared and the action SHALL reappear both on its priority card and in the pinned list, still pinned

#### Scenario: Waiting action in the pinned list
- **WHEN** a pinned action is waiting
- **THEN** its pinned row SHALL show the hourglass treatment instead of a checkbox and complete only via its overflow, matching the card behavior
