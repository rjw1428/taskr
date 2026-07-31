## ADDED Requirements

### Requirement: Preserved color-coded priority mapping
The system SHALL keep the task card's semantic priority-to-color mapping: high = red family, medium = amber/gold family, low = green family, info = neutral. The redesign MAY retune the exact shades but MUST NOT change which color represents which priority.

#### Scenario: Priority determines card color
- **WHEN** a task with a given priority (high, medium, low, info) is rendered
- **THEN** the card fill uses the palette entry for that priority in the current brightness
- **AND** the high/medium/low/info → red/amber/green/neutral mapping is unchanged from before the redesign

### Requirement: Priority palettes for light and dark
The system SHALL define priority card palettes for both light and dark themes such that the card fill and its text/icons meet legibility (WCAG AA for the task title) on each background.

#### Scenario: Card in dark mode
- **WHEN** a priority card is shown in dark mode
- **THEN** it uses the dark-variant priority fill with a light-tuned on-color, and the title is clearly readable

#### Scenario: Card in light mode
- **WHEN** a priority card is shown in light mode
- **THEN** it uses the light-variant priority fill with an on-color that keeps the title clearly readable (no light-on-light)

### Requirement: Preserved card structure and behavior
The system SHALL preserve the existing task card structure and interactions: checkbox completion, tap-to-expand for description/tags, reorder drag handle, the overflow action menu, goal/recurring indicators, and multi-day connected corner radii.

#### Scenario: Completing a task
- **WHEN** the user checks a task's checkbox
- **THEN** the task is marked complete and the card shows its completed (dimmed) state, exactly as before
- **AND** scoring/goal side effects are unchanged

#### Scenario: Expanding a task
- **WHEN** the user taps a card that has a description or tags
- **THEN** the card expands to reveal them and collapses on a second tap

#### Scenario: Multi-day task rendering
- **WHEN** a task spans multiple days (start, middle, end segments)
- **THEN** the card's corner radii connect across segments as they did before the redesign

### Requirement: Refined card chrome and completion motion
The system SHALL restyle the card's chrome (elevation, corner radius, border, spacing) to the "quiet depth" direction and animate completion and expansion using the motion tokens.

#### Scenario: Completion celebration
- **WHEN** a task is completed and reduced motion is off
- **THEN** a completion animation plays (card state animates and a celebratory effect fires)

#### Scenario: Completion with reduced motion
- **WHEN** a task is completed and reduced motion is on
- **THEN** the card updates to its completed state without the celebratory animation
