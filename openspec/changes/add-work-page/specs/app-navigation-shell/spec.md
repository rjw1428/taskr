## MODIFIED Requirements

### Requirement: Themed app shell
The system SHALL render the app bar, bottom navigation bar, and floating action button(s) using the design system, consistent across light and dark themes.

#### Scenario: Shell reflects the active theme
- **WHEN** the app is displayed in either light or dark mode
- **THEN** the app bar, bottom navigation, and action button use themed surface, accent, and text colors from the token layer
- **AND** the selected navigation tab is visually distinct from unselected tabs

#### Scenario: Existing tabs and destinations are preserved
- **WHEN** the shell is shown
- **THEN** the navigation destinations are, in order: List, Work, Performance, Goals, Backlog, People
- **AND** selecting a destination navigates to the same screen as before, with Work navigating to the Work page
- **AND** the Work destination uses the `corporate_fare` icon

### Requirement: Context-appropriate action button
The system SHALL present a floating action button whose action matches the current tab, preserving existing behaviors (including add-task, and the long-press "add divider" affordance on the task lists).

#### Scenario: Add action per tab
- **WHEN** a tab that supports creation is active
- **THEN** the action button triggers that tab's create flow (e.g. add task, add work item, add goal, add accomplishment, add person)

#### Scenario: Long-press divider affordance preserved
- **WHEN** the user long-presses the action button on the Today or Backlog tab
- **THEN** the add-divider dialog appears, as it did before the redesign

#### Scenario: Action follows the tab, not its index
- **WHEN** a tab's position in the bar changes
- **THEN** tests verify the action button behavior by tab label so a shifted index cannot silently attach the wrong create flow

## ADDED Requirements

### Requirement: Programmatic tab selection
The system SHALL expose a way for the app shell to request a bottom-navigation tab by route, so that quick actions and notifications can land on a specific tab.

#### Scenario: Request while home is mounted
- **WHEN** a route such as `/work` is requested
- **THEN** the home screen selects that tab exactly as if the user had tapped it, and the request is cleared

#### Scenario: Unknown route
- **WHEN** a route that is not in the route config is requested
- **THEN** the home screen ignores it and stays on the current tab
