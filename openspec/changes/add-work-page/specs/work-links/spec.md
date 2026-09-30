## ADDED Requirements

### Requirement: URL detection
The system SHALL detect URLs in work item text using a pure tokenizer that matches `http://` and `https://` URLs and bare `www.` prefixed hosts, trimming trailing punctuation (such as `.`, `,`, `)`, `;`) from a match.

#### Scenario: HTTPS link in a sentence
- **WHEN** the text is "See https://example.atlassian.net/browse/ABC-123 for details."
- **THEN** the tokenizer SHALL yield a link token for `https://example.atlassian.net/browse/ABC-123` and plain tokens for the surrounding text, excluding the trailing period

#### Scenario: Bare www link
- **WHEN** the text contains "www.github.com/org/repo/pull/42"
- **THEN** the tokenizer SHALL yield a link token whose target is `https://www.github.com/org/repo/pull/42`

#### Scenario: No links
- **WHEN** the text contains no URL
- **THEN** the tokenizer SHALL yield a single plain token equal to the input

#### Scenario: Multiple links
- **WHEN** the text contains two URLs separated by words
- **THEN** the tokenizer SHALL yield two link tokens with the correct plain tokens between them

### Requirement: Links render as tappable text
The system SHALL render work item titles, notes, next-action text, and progress updates through a shared link-aware text widget that styles detected URLs with the accent color and underline and opens them in the system browser on tap.

#### Scenario: Tap opens externally
- **WHEN** the user taps a rendered link
- **THEN** the system SHALL launch the URL in an external application (browser or the app registered for it)

#### Scenario: Plain text unaffected
- **WHEN** text has no links
- **THEN** it SHALL render exactly as ordinary body text with no link styling

#### Scenario: Paste creates a link with no extra steps
- **WHEN** the user pastes a URL into the notes field and saves
- **THEN** the saved notes SHALL render that URL as a tappable link without any markup or additional action

#### Scenario: Launcher failure is non-fatal
- **WHEN** the URL cannot be launched
- **THEN** the system SHALL show a snackbar explaining the link could not be opened and SHALL NOT crash
