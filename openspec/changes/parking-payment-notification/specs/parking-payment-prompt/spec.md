## ADDED Requirements

### Requirement: Parking prompt opt-in

The system SHALL send parking prompts only to users who have explicitly opted
in via a `parkingAlert` boolean field on their `todos/{uid}` document. The flag
SHALL be independent of the existing `trainAlert` flag, so a user can receive
train status updates without parking prompts and vice versa.

#### Scenario: User has opted in

- **WHEN** the daily train schedule runs and a user's `todos/{uid}` document has
  `parkingAlert` set to `true`
- **THEN** the system schedules a parking prompt for that user

#### Scenario: User has not opted in

- **WHEN** the daily train schedule runs and a user's `todos/{uid}` document has
  `parkingAlert` absent or set to `false`
- **THEN** the system schedules no parking prompt for that user, regardless of
  the value of `trainAlert`

#### Scenario: Opt-in is readable only by its owner

- **WHEN** any authenticated user other than the owner attempts to read
  `todos/{uid}.parkingAlert`
- **THEN** Firestore rules deny the read

### Requirement: Prompt scheduled at the Work Train start time

The system SHALL schedule the parking prompt to be delivered at the `startTime`
of the current day's task titled "Work Train", interpreted in the
`America/New_York` timezone. Delivery SHALL use a Cloud Task with an explicit
schedule time rather than a fixed recurring cron.

#### Scenario: Work Train task exists with a start time

- **WHEN** the daily schedule runs for an opted-in user and today's tasks include
  one titled "Work Train" with `startTime` of `08:15`
- **THEN** the system enqueues a Cloud Task scheduled for 08:15
  `America/New_York` on today's date

#### Scenario: No Work Train task today

- **WHEN** the daily schedule runs for an opted-in user and today's tasks include
  no task titled "Work Train"
- **THEN** the system enqueues no parking prompt and logs the reason

#### Scenario: Work Train task has no start time

- **WHEN** the daily schedule runs for an opted-in user and today's "Work Train"
  task has no `startTime`
- **THEN** the system enqueues no parking prompt and logs the reason

#### Scenario: Scheduling runs after UTC has rolled over

- **WHEN** the scheduling function runs at a local time where the UTC date is
  already the following day
- **THEN** it looks up the task under the current `America/New_York` date, not
  the UTC date

#### Scenario: Start time has already passed

- **WHEN** the computed schedule time is earlier than the current time
- **THEN** the system enqueues the task without error and the prompt is delivered
  promptly rather than being dropped

### Requirement: Duplicate prompts are prevented at scheduling time

The system SHALL enqueue at most one parking prompt per user per day. The Cloud
Task SHALL be created with a deterministic name derived from the user ID and the
date, so that a repeated scheduling run collides with the existing task instead
of creating a second one.

#### Scenario: Schedule runs twice on the same day

- **WHEN** the scheduling function runs a second time on the same date for the
  same opted-in user
- **THEN** the Cloud Tasks API rejects the duplicate as already existing, the
  system treats it as a no-op, and exactly one prompt is delivered

### Requirement: Prompt delivery re-validates before sending

At delivery time the system SHALL re-check preconditions before sending the
notification, because state may have changed since the task was enqueued.

#### Scenario: Task was deleted after scheduling

- **WHEN** the prompt is delivered but the "Work Train" task no longer exists
- **THEN** the system sends no notification and completes successfully without
  causing a Cloud Tasks retry

#### Scenario: User opted out after scheduling

- **WHEN** the prompt is delivered but the user's `parkingAlert` is no longer
  `true`
- **THEN** the system sends no notification and completes successfully

#### Scenario: FCM registration token is dead

- **WHEN** sending the prompt fails with
  `messaging/registration-token-not-registered`
- **THEN** the system clears the stored `fcmToken` for that user and completes
  successfully without causing a Cloud Tasks retry

#### Scenario: User has no FCM token

- **WHEN** the prompt is delivered but the user has no stored `fcmToken`
- **THEN** the system sends no notification, logs the reason, and completes
  successfully

### Requirement: Prompt is suppressed when parking is already active

The client SHALL check the parking service's `/status` endpoint before displaying
the prompt, and SHALL suppress the notification when an active session is already
covering the vehicle. The check SHALL fail open: any outcome other than an
unambiguous confirmation of an active session results in the prompt being
displayed, because a missed prompt risks a day of unpaid parking while a
redundant one costs only a tap.

#### Scenario: A session is already active

- **WHEN** the prompt arrives and `/status` responds `200` with a non-empty
  `active` array
- **THEN** the client displays no notification

#### Scenario: No session is active

- **WHEN** the prompt arrives and `/status` responds `200` with an empty `active`
  array
- **THEN** the client displays the prompt

#### Scenario: Status check is unreachable

- **WHEN** the prompt arrives and the `/status` request fails with a network
  error or times out
- **THEN** the client displays the prompt

#### Scenario: Status check reports an upstream problem

- **WHEN** the prompt arrives and `/status` responds `409` or `502`
- **THEN** the client displays the prompt

### Requirement: Prompt is an actionable notification with Yes and No

The system SHALL display the parking prompt as a notification offering two
actions: one to trigger payment and one to dismiss. The notification SHALL be
delivered at high priority on the high-importance Android channel so it surfaces
while the device is idle, and SHALL be displayed whether the app is in the
foreground, backgrounded, or not running.

#### Scenario: Exactly one notification results from one push

- **WHEN** a single parking prompt push is delivered while the app is not in the
  foreground
- **THEN** exactly one notification is displayed, drawn by the client and
  carrying both actions, with no second system-drawn copy

#### Scenario: Prompt is displayed with both actions

- **WHEN** the client receives a message identifying itself as a parking prompt
- **THEN** it displays a notification asking whether to pay for parking, with a
  Yes action and a No action

#### Scenario: Prompt arrives while the app is not running

- **WHEN** the parking prompt arrives and the app has been terminated
- **THEN** the notification is still displayed and both actions remain functional

#### Scenario: User selects No

- **WHEN** the user selects the No action
- **THEN** the notification is dismissed, no network request is made, and no
  state is written

### Requirement: The prompt remains answerable inside the app

The notification's action buttons SHALL NOT be the only way to answer the
prompt. Opening the app from the prompt, or reaching the prompt in the in-app
notification centre, SHALL present the same yes/no question, because the
notification's buttons are unavailable once it has been dismissed or its body
tapped.

#### Scenario: User taps the notification body

- **WHEN** the user taps the body of the prompt rather than one of its actions
- **THEN** the app opens and presents the same yes/no question

#### Scenario: User taps the body while the app is not running

- **WHEN** the tap launches the app from a terminated state
- **THEN** the question is presented once the app is ready

#### Scenario: User opens an already-dismissed prompt from the notification centre

- **WHEN** the user selects a recorded parking prompt in the in-app notification
  centre
- **THEN** the same yes/no question is presented

#### Scenario: In-app answer reports its outcome inline

- **WHEN** the user answers yes from inside the app
- **THEN** the outcome is reported within the app rather than as another
  notification, and still does not claim that parking has been paid for

### Requirement: Yes triggers an authenticated parking request

Selecting the Yes action SHALL issue `GET https://api.ryanwilk.com/parking/park`
with the parking trigger token supplied in an `Authorization: Bearer` header.
The token SHALL NOT be sent as a query parameter, and SHALL NOT be committed to
source control.

#### Scenario: User selects Yes

- **WHEN** the user selects the Yes action
- **THEN** the client sends a GET request to the parking endpoint carrying the
  bearer token in the `Authorization` header, and dismisses the prompt

#### Scenario: Token is absent from configuration

- **WHEN** the Yes action fires but no parking trigger token is configured
- **THEN** the client makes no request and informs the user the feature is not
  configured

#### Scenario: Token is rejected

- **WHEN** the parking service responds `401`
- **THEN** the client informs the user that the parking request was not accepted
  and does not retry

### Requirement: A payment that cannot succeed is reported immediately

The system SHALL check the parking service's upstream session before triggering
a purchase, and SHALL notify the user without sending the request when that
session is known to be dead. The service's own result push is best-effort, so a
failure that is already knowable MUST NOT be left to a message that may never
arrive. The check SHALL fail open: an indeterminate result proceeds with the
request.

#### Scenario: Upstream session is expired

- **WHEN** the user answers yes and the service reports `hasSession` false
- **THEN** no purchase request is sent, and the user is notified that the parking
  account needs signing in again and that nothing was charged

#### Scenario: Upstream session is healthy

- **WHEN** the service reports `hasSession` true
- **THEN** the purchase request is sent as normal

#### Scenario: Upstream health cannot be determined

- **WHEN** the health check fails, times out, or omits the field
- **THEN** the purchase request is still sent, because treating unknown as dead
  would turn a service hiccup into unpaid parking

### Requirement: An accepted request is never reported as a completed payment

The system SHALL NOT tell the user that parking is paid for on the basis of the
trigger response. The parking service is fire-and-forget: a `200` means the
request was accepted and the purchase is running, not that parking has been paid
for.

#### Scenario: Request is accepted

- **WHEN** the parking service responds `200` with `success: true` and a
  `requestId`
- **THEN** the client confirms only that the request was sent, and does not state
  or imply that payment has completed

#### Scenario: Request could not be sent

- **WHEN** the trigger request fails because of a network error or a non-`200`,
  non-`401` response
- **THEN** the client informs the user that the request was not sent, so the
  failure is distinguishable from a request that succeeded but has no result yet

### Requirement: Payment outcome is surfaced to the user

The system SHALL surface the payment outcome that the parking service reports
asynchronously as a separate push carrying `type` of `septapark` and a `status`.
The system SHALL distinguish the `needs-auth` status, for which retrying can
never succeed because it requires a person to complete an SMS verification.

#### Scenario: Payment succeeded

- **WHEN** a push arrives with `type` of `septapark` and `status` of `paid`
- **THEN** the user is shown that parking was paid for

#### Scenario: Session was already active

- **WHEN** a push arrives with `status` of `skipped`
- **THEN** the user is shown that parking was already covered and nothing was
  bought

#### Scenario: Upstream authentication expired

- **WHEN** a push arrives with `status` of `needs-auth`
- **THEN** the user is told that the parking account needs to be re-authenticated
  by a person, and is not invited to retry the payment

#### Scenario: Outcome push carries no actions

- **WHEN** a push arrives with `type` of `septapark`
- **THEN** it is handled as an informational notification and is not mistaken for
  an actionable prompt

### Requirement: Locally raised notifications reach the in-app inbox

Every parking notification the client raises SHALL also be recorded to the
in-app notification centre. Cloud Functions record the messages they send, but
outcome notifications are drawn on the device and the parking service's result
pushes bypass the backend entirely, so neither would otherwise leave any trace
once dismissed. Recording SHALL be best-effort and MUST NOT prevent the
notification from being shown.

#### Scenario: Payment outcome is recorded

- **WHEN** the client raises a notification for a parking trigger outcome or a
  result push
- **THEN** a matching entry appears in the in-app notification centre

#### Scenario: Answering from inside the app is recorded

- **WHEN** the user answers yes via the in-app dialog and the outcome is shown as
  a transient message
- **THEN** the outcome is still recorded, so dismissing it loses nothing

#### Scenario: Recording fails

- **WHEN** the inbox write fails
- **THEN** the notification is still displayed to the user

### Requirement: Notification actions dispatch on the selected action

The client SHALL dispatch notification handling on the action the user actually
selected, rather than assuming a single action. Existing notification actions
SHALL continue to work through this dispatch.

#### Scenario: A multi-action notification is handled

- **WHEN** the user selects one of several actions on a notification
- **THEN** the client executes the handler for the selected action and no other

#### Scenario: Existing wind task action still works

- **WHEN** the user selects the existing `add-wind-task` action
- **THEN** the wind task is created as before
