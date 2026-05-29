## ADDED Requirements

### Requirement: Settings page hosts a calendar connection control

The app SHALL expose a Settings page reachable from the main navigation. The first item on the Settings page MUST be "Google Calendar," showing the current connection state and an action to connect or disconnect.

#### Scenario: Disconnected state
- **WHEN** the user opens Settings and has not connected a calendar
- **THEN** the Google Calendar row shows "Not connected" with a "Connect" button

#### Scenario: Connected state
- **WHEN** the user opens Settings and has previously connected
- **THEN** the row shows "Connected" with the connection date and a "Disconnect" button

### Requirement: Connect flow requests incremental calendar scope

Tapping "Connect" SHALL request the OAuth scope `https://www.googleapis.com/auth/calendar` from the already-signed-in Google account. The app MUST capture a `serverAuthCode` from the consent response.

#### Scenario: Successful consent
- **WHEN** the user taps "Connect" and grants the requested scope
- **THEN** the app captures the `serverAuthCode`
- **AND** sends it to the `exchangeCalendarAuthCode` Cloud Function

#### Scenario: User cancels consent
- **WHEN** the user dismisses the consent screen without granting
- **THEN** the Settings row remains "Not connected" and no token is stored
- **AND** the app shows a transient "Connection cancelled" message

### Requirement: Server-side code exchange stores refresh token

The `exchangeCalendarAuthCode` Cloud Function SHALL exchange the `serverAuthCode` for a refresh token using Google's OAuth token endpoint, then store the refresh token at `todos/{uid}.calendarRefreshToken` and set `calendarConnectedAt` to the server timestamp.

#### Scenario: Successful exchange
- **WHEN** the function receives a valid `serverAuthCode` for an authenticated user
- **THEN** Google returns a refresh token plus an initial access token
- **AND** the function writes `calendarRefreshToken` and `calendarConnectedAt` to `todos/{uid}`
- **AND** returns `{ ok: true }` to the caller

#### Scenario: Failed exchange
- **WHEN** the token exchange returns an error from Google
- **THEN** the function returns the error to the caller without storing anything
- **AND** the Settings UI surfaces the error to the user

### Requirement: Refresh token is not readable by the client

The Firestore field `calendarRefreshToken` SHALL be protected by security rules such that the client (using the user's auth) cannot read it directly. Only the Admin SDK (Cloud Functions) may access it.

#### Scenario: Client read attempt
- **WHEN** the Flutter app attempts to read `todos/{uid}.calendarRefreshToken`
- **THEN** the read is denied by the security rules
- **AND** the app instead reads `calendarConnectedAt` to determine connection state

### Requirement: Disconnect flow revokes and clears the token

Tapping "Disconnect" SHALL call a `disconnectCalendar` Cloud Function that revokes the refresh token with Google and clears `calendarRefreshToken`, `calendarSyncToken`, and `calendarConnectedAt` from Firestore.

#### Scenario: Successful disconnect
- **WHEN** the user taps "Disconnect" and confirms
- **THEN** the function calls Google's revoke endpoint with the stored refresh token
- **AND** removes all three fields from `todos/{uid}`
- **AND** the Settings row returns to "Not connected"

#### Scenario: Token already invalid on disconnect
- **WHEN** the stored refresh token has already been revoked outside the app
- **THEN** the function clears the three Firestore fields regardless of Google's response
- **AND** returns success to the caller
