## ADDED Requirements

### Requirement: System sends 5 PM reminder for incomplete goal tasks
The system SHALL run a Cloud Function `goalReminder5pm` on schedule (`every day 17:00`) that checks for incomplete goal tasks due today and sends a push notification to the user via FCM.

#### Scenario: User has incomplete goal tasks at 5 PM
- **WHEN** the `goalReminder5pm` function fires and the user has 2 incomplete goal tasks for today
- **THEN** the system sends an FCM notification with a message like "You have 2 goal tasks remaining today" including the goal name(s)

#### Scenario: User has no incomplete goal tasks at 5 PM
- **WHEN** the `goalReminder5pm` function fires and all of the user's goal tasks for today are completed
- **THEN** the system does not send a notification

#### Scenario: User has no goal tasks for today
- **WHEN** the `goalReminder5pm` function fires and the user has no goal-linked tasks scheduled for today
- **THEN** the system does not send a notification

#### Scenario: User has no FCM token
- **WHEN** the function finds incomplete goal tasks but the user has no stored FCM token
- **THEN** the system skips that user without error

### Requirement: System sends 9 PM reminder for incomplete goal tasks
The system SHALL run a Cloud Function `goalReminder9pm` on schedule (`every day 21:00`) that checks for incomplete goal tasks due today and sends a second push notification via FCM.

#### Scenario: User still has incomplete goal tasks at 9 PM
- **WHEN** the `goalReminder9pm` function fires and the user has 1 incomplete goal task for today
- **THEN** the system sends an FCM notification with an escalated message like "Don't forget: 1 goal task still needs your attention tonight"

#### Scenario: User completed all goal tasks between 5 PM and 9 PM
- **WHEN** the `goalReminder9pm` function fires and all goal tasks for today are now completed
- **THEN** the system does not send a notification

### Requirement: Reminder notifications are actionable
Reminder notifications SHALL include data that allows the app to navigate to the relevant task or goal when the user taps the notification.

#### Scenario: User taps reminder notification
- **WHEN** the user taps a goal reminder notification
- **THEN** the app opens and navigates to the daily task list for today, showing the incomplete goal tasks

#### Scenario: Notification received while app is in foreground
- **WHEN** a goal reminder notification arrives while the app is open
- **THEN** the system displays an in-app notification banner rather than a system notification

### Requirement: Reminders only fire for active goals
The system SHALL only send reminders for tasks linked to goals with status `active`. Tasks from deleted or completed goals SHALL not trigger reminders.

#### Scenario: Goal was deleted but tasks remain
- **WHEN** the reminder function finds an incomplete task whose parent goal has status `deleted`
- **THEN** the system does not send a reminder for that task

#### Scenario: Goal has expired (auto-completed)
- **WHEN** the reminder function finds a task whose parent goal has status `completed`
- **THEN** the system does not send a reminder for that task
