# notification-center Specification

## Purpose
TBD - created by archiving change add-habits-and-notifications. Update Purpose after archive.
## Requirements
### Requirement: Sent notifications are persisted
The system SHALL record a notification to the user's data whenever it sends an FCM message, so notifications can be reviewed later. Each record SHALL include the title, body, any data payload, a type, a sent timestamp, and a read flag. Recording a notification SHALL NOT block or fail the actual push send.

#### Scenario: A goal reminder is captured
- **WHEN** the backend sends a goal-reminder push
- **THEN** a corresponding notification record is written for that user with read = false

#### Scenario: Recording failure is non-fatal
- **WHEN** writing the notification record fails
- **THEN** the FCM push is still delivered and the error is only logged

### Requirement: In-app notification center
The system SHALL provide a screen, reachable from the upper-right overflow menu, that lists the user's notifications newest-first, distinguishes read from unread, and lets the user mark items read, delete individual items, and clear all.

#### Scenario: Open and review
- **WHEN** the user opens Notifications from the menu
- **THEN** past notifications are listed newest-first with their title, body, and relative time
- **AND** unread notifications are visually distinct

#### Scenario: Mark read and clear
- **WHEN** the user taps a notification
- **THEN** it is marked read
- **WHEN** the user chooses "Clear all"
- **THEN** the list is emptied

### Requirement: Unread badge
The system SHALL show an unread-count badge on the menu entry point when there are unread notifications.

#### Scenario: Badge reflects unread count
- **WHEN** there are unread notifications
- **THEN** the menu icon shows a badge with the unread count
- **WHEN** all are read
- **THEN** the badge disappears

#### Scenario: Empty state
- **WHEN** there are no notifications (e.g. before the backend change is deployed)
- **THEN** the center shows an empty state and does not error

