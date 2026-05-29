## Why

Taskr helps users manage daily tasks, but it lacks a way to drive long-term personal growth. Users have no mechanism to set aspirational goals ("learn piano", "be a better friend"), break them into actionable steps, and sustain progress over weeks or months. A goals feature — powered by LLM-generated weekly task plans — turns Taskr from a to-do list into a personal development tool.

## What Changes

- **Goal creation flow**: Users define a goal with a title, optional description, timeframe (1 week, 1 month, 3 months, 6 months, 1 year), and frequency (daily, N times/week, or auto — where the LLM decides cadence).
- **LLM-powered task generation**: Each goal is sent to an LLM (Firebase VertexAI) which generates the next week's worth of concrete, actionable tasks. The LLM receives the goal definition plus a history of completed/skipped tasks to build progressively on prior work.
- **Weekly task regeneration**: A scheduled Cloud Function runs weekly to generate the next batch of tasks for each active goal. Tasks are inserted into the user's daily task list with a goal tag/association.
- **Goal management from tasks**: Any task linked to a goal surfaces a "Manage Goal" action, allowing the user to view, edit, or delete the goal (including all future generated tasks).
- **Reminder notifications**: If a goal-related task isn't completed by 5 PM, a push notification reminds the user. A second reminder fires at 9 PM if still incomplete.
- **Goal lifecycle**: Goals automatically expire when their timeframe elapses. Users can also manually complete or delete a goal at any time.

## Capabilities

### New Capabilities
- `goal-crud`: Creating, reading, updating, and deleting goals. Firestore data model, goal form UI, goal list/detail views.
- `goal-task-generation`: LLM-powered weekly task generation from goals. Prompt engineering, task history context, VertexAI integration, and the scheduled Cloud Function for weekly regeneration.
- `goal-task-linking`: Associating generated tasks with their parent goal. UI affordances on task items to navigate to/manage the parent goal. Cascade delete of future tasks when a goal is removed.
- `goal-reminders`: 5 PM and 9 PM push notification reminders for incomplete goal tasks. Scheduled Cloud Function to check completion status and send FCM notifications.

### Modified Capabilities
_(none — this is a new feature module; existing task and notification infrastructure is extended but its requirements don't change)_

## Impact

- **Firestore**: New collections `todos/{userId}/goals/{goalId}` for goal definitions and task generation history.
- **Cloud Functions**: Two new scheduled functions — weekly task generation and daily reminder checks (5 PM / 9 PM).
- **VertexAI**: New prompt templates for goal-to-task decomposition, consuming the existing `ai.service.dart` integration.
- **Task model**: Tasks gain an optional `goalId` field to link back to their parent goal.
- **Navigation**: The existing placeholder `/goals` route becomes a full feature. Home screen "Add a goal" action becomes functional.
- **Dependencies**: No new Flutter packages expected — existing `rrule`, `firebase_messaging`, and provider infrastructure suffice.
