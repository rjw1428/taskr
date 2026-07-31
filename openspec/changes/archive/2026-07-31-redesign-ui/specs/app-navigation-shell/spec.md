## ADDED Requirements

### Requirement: Themed app shell
The system SHALL render the app bar, bottom navigation bar, and floating action button(s) using the design system, consistent across light and dark themes.

#### Scenario: Shell reflects the active theme
- **WHEN** the app is displayed in either light or dark mode
- **THEN** the app bar, bottom navigation, and action button use themed surface, accent, and text colors from the token layer
- **AND** the selected navigation tab is visually distinct from unselected tabs

#### Scenario: Existing tabs and destinations are preserved
- **WHEN** the redesigned shell is shown
- **THEN** all existing navigation destinations (Today, Performance, Goals, Backlog, People) remain present in their current order
- **AND** selecting a destination navigates to the same screen as before

### Requirement: Context-appropriate action button
The system SHALL present a floating action button whose action matches the current tab, preserving existing behaviors (including add-task, and the long-press "add divider" affordance on the task lists).

#### Scenario: Add action per tab
- **WHEN** a tab that supports creation is active
- **THEN** the action button triggers that tab's create flow (e.g. add task, add goal, add accomplishment, add person)

#### Scenario: Long-press divider affordance preserved
- **WHEN** the user long-presses the action button on the Today or Backlog tab
- **THEN** the add-divider dialog appears, as it did before the redesign

### Requirement: Animated navigation transitions
The system SHALL animate transitions between tabs and when pushing/popping detail screens, using the centralized motion tokens.

#### Scenario: Switching tabs
- **WHEN** the user selects a different bottom-navigation tab
- **THEN** the content transitions with a themed motion (e.g. shared-axis/fade) rather than an instant swap
- **AND** the transition respects the reduced-motion setting

#### Scenario: Opening a detail screen
- **WHEN** the user opens a detail screen (e.g. a person, goal, or task series)
- **THEN** the navigation uses an animated transition consistent with the motion tokens
