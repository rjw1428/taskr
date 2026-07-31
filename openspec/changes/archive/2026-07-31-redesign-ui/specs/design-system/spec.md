## ADDED Requirements

### Requirement: Centralized design tokens
The system SHALL define color, typography, spacing, corner-radius, elevation, and motion values in a single token layer that all UI consumes, rather than inline literals per widget.

#### Scenario: Widgets read spacing and radius from tokens
- **WHEN** a screen or component needs spacing, corner radius, or elevation
- **THEN** it reads the value from the shared token layer (via `Theme`, `ColorScheme`, or the `AppTokens` theme extension)
- **AND** no new UI code introduces hardcoded `Colors.white`, `Colors.black`, or magic spacing/radius literals

#### Scenario: App-specific tokens available through the theme
- **WHEN** a widget needs an app-specific token (priority palette or a named motion duration/curve)
- **THEN** it retrieves it from `Theme.of(context).extension<AppTokens>()`
- **AND** the value resolves to the correct variant for the active brightness

### Requirement: Light and dark themes with a user override
The system SHALL provide both a light and a dark theme built on Material 3. It SHALL follow the operating system appearance by default, and SHALL let the user override the appearance (System / Light / Dark) from Settings. The chosen preference SHALL persist across app restarts.

#### Scenario: Following the OS by default
- **WHEN** the user has not chosen an appearance override
- **THEN** the app follows the operating system appearance (dark → dark theme, light → light theme)
- **AND** it updates without a restart when the device appearance changes at runtime

#### Scenario: User overrides to Light or Dark
- **WHEN** the user selects Light (or Dark) in Settings
- **THEN** the app immediately renders that theme regardless of the OS setting
- **AND** the choice still applies after the app is closed and reopened

#### Scenario: User selects System
- **WHEN** the user selects System in Settings
- **THEN** the app resumes following the operating system appearance

#### Scenario: Legibility in both themes
- **WHEN** either theme is active
- **THEN** all text and icons remain legible (no dark-on-dark or light-on-light) because colors resolve from `ColorScheme`

### Requirement: Deliberate typography scale
The system SHALL define a typography scale mapped onto Material text roles, with a display face used for titles/large figures and a legible body face for content, replacing the placeholder text theme.

#### Scenario: Text color comes from the color scheme
- **WHEN** any themed text is rendered
- **THEN** its color derives from `ColorScheme` (e.g. `onSurface`), not from the text style itself
- **AND** the previous red/green/blue body text styles are no longer present

### Requirement: Reusable styled components
The system SHALL provide a set of shared, themed components (at minimum: a surface/card container, a section header, primary and secondary buttons, a text input decoration, an empty-state, and a bottom-sheet shell) that screens reuse instead of re-implementing chrome.

#### Scenario: A screen composes from shared components
- **WHEN** a screen presents a card, section header, primary action, or empty state
- **THEN** it uses the corresponding shared component
- **AND** that component automatically reflects the active light/dark theme and tokens

### Requirement: Reduced-motion support
The system SHALL respect the operating system's reduce-motion / disable-animations setting across all animated UI.

#### Scenario: Reduced motion is enabled
- **WHEN** the OS reduce-motion setting is on
- **THEN** transitions degrade to instant or simple opacity changes
- **AND** decorative/celebratory animations (e.g. completion confetti) are suppressed
