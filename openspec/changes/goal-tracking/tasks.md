## 1. Data Model & Service Layer

- [x] 1.1 Add `Goal` model class to `lib/services/models.dart` with fields: id, title, description, timeframe, frequency, frequencyCount, startDate, endDate, status, createdAt, modifiedAt
- [x] 1.2 Add `Generation` model class to `lib/services/models.dart` with fields: id, generatedAt, weekStart, weekEnd, taskIds, prompt, response, completedTaskIds, skippedTaskIds
- [x] 1.3 Add optional `goalId` field to the existing `Task` model
- [x] 1.4 Create `lib/services/goal.service.dart` with Firestore CRUD operations for goals at `todos/{userId}/goals/{goalId}`
- [x] 1.5 Add generation record CRUD methods to `GoalService` for subcollection at `todos/{userId}/goals/{goalId}/generations/{generationId}`
- [x] 1.6 Add real-time stream for user's active goals (listen to goals where status == active)
- [x] 1.7 Add method to query all tasks by `goalId` across date partitions (using generation record `taskIds` as source of truth)

## 2. LLM Task Generation

- [x] 2.1 Create goal-to-task prompt template in `GoalService` that includes: goal definition, frequency, week number, and completion history
- [x] 2.2 Implement `generateTasksForGoal()` method using existing `FirebaseVertexAI` (gemini-1.5-flash) — send prompt, parse JSON response into Task objects
- [x] 2.3 Add JSON schema validation for LLM response (array of objects with title, description, suggestedDay, effort)
- [x] 2.4 Implement retry logic: on parse failure, retry once with stricter prompt; on second failure, log error and surface to user
- [x] 2.5 Implement task distribution logic: map LLM-suggested days to actual dates for the coming week, write tasks to `todos/{userId}/tasks/{date}/items/`
- [x] 2.6 Create generation record after successful task creation with prompt, response, and taskIds
- [x] 2.7 Add history summarization for LLM context: recent 2-3 weeks in detail, older weeks as aggregated stats

## 3. Goal CRUD UI

- [x] 3.1 Create `lib/goals/goal_form.dart` — modal bottom sheet with fields: title, description, timeframe picker (segmented button), frequency picker (segmented button), frequency count input (shown when N-times/week selected)
- [x] 3.2 Create `lib/goals/goal_list.dart` — goals tab page showing active goals with title, time remaining, and frequency; empty state when no goals exist
- [x] 3.3 Create `lib/goals/goal_detail_page.dart` — detail page showing goal info, progress summary (weeks elapsed, tasks completed/total, completion rate), Edit and Delete actions, and Regenerate button
- [x] 3.4 Wire up the existing `/goals` placeholder route in `lib/routing.dart` to `GoalListPage`
- [x] 3.5 Wire up the "Add a goal" FAB in `lib/home/home.dart` to open the goal form
- [x] 3.6 Implement goal edit flow: reuse goal form pre-populated with existing values, recompute endDate on timeframe change
- [x] 3.7 Implement goal delete flow: confirmation dialog, set status to `deleted`, cascade delete uncompleted tasks, preserve completed tasks

## 4. Task-Goal Linking UI

- [x] 4.1 Update `lib/task_list/task_item.dart` to show a goal indicator (icon + goal title) when task has a `goalId`
- [x] 4.2 Add "View Goal" action to the task popup menu when `goalId` is present
- [x] 4.3 Implement navigation from "View Goal" action to goal detail page
- [x] 4.4 Update task completion handler to backfill `completedTaskIds` on the corresponding generation record

## 5. Manual Regeneration

- [x] 5.1 Add "Regenerate" button to goal detail page
- [x] 5.2 Implement regeneration flow: delete uncompleted tasks for current week, call LLM for fresh batch, create new tasks, update generation record
- [x] 5.3 Handle edge case: all tasks already completed — generate additional tasks for remaining days without deleting

## 6. Goal Auto-Completion

- [x] 6.1 Add expiry check in `GoalService` stream: when loading goals, mark any active goal past `endDate` as `completed`
- [x] 6.2 Build completion summary view on goal detail page: weeks active, tasks completed out of total, completion percentage
- [x] 6.3 Show completed goals in a separate section of the goals list (collapsible)

## 7. Cloud Functions — Weekly Generation

- [x] 7.1 Create `generateGoalTasks` scheduled Cloud Function in `firebase/functions/src/index.ts` triggered `every sunday 20:00`
- [x] 7.2 Implement user iteration: query all users with at least one active goal
- [x] 7.3 For each user/goal: fetch latest generation record, cross-reference taskIds with task documents to determine completed vs. skipped, build prompt, call VertexAI, write tasks, write generation record
- [x] 7.4 Add error handling: log failures per goal, continue processing other goals/users
- [x] 7.5 Add HTTP test endpoint `generateGoalTasksTest` for manual triggering during development

## 8. Cloud Functions — Reminder Notifications

- [x] 8.1 Create `goalReminder5pm` scheduled Cloud Function triggered `every day 17:00`
- [x] 8.2 Create `goalReminder9pm` scheduled Cloud Function triggered `every day 21:00`
- [x] 8.3 Implement reminder logic: for each user with active goals, query today's tasks where goalId != null and completed == false, send FCM notification with task count and goal name(s)
- [x] 8.4 Skip users with no FCM token; skip tasks linked to deleted/completed goals
- [x] 8.5 Include navigation data in notification payload so tapping opens the daily task list
- [x] 8.6 Handle foreground notification display in `lib/services/messaging.dart` — show in-app banner for goal reminders

## 9. Integration & Polish

- [x] 9.1 Register `GoalService` as a provider in the app's provider tree
- [x] 9.2 Trigger initial task generation immediately after goal creation (client-side via GoalService)
- [ ] 9.3 Verify goal tasks appear correctly in daily task list with ordering, push, and completion working
- [ ] 9.4 Verify cascade delete removes uncompleted tasks and preserves completed ones
- [ ] 9.5 Test weekly Cloud Function locally using Firebase emulator
- [ ] 9.6 Test reminder Cloud Functions locally using Firebase emulator
- [ ] 9.7 End-to-end test: create goal → see generated tasks → complete some → weekly regen → verify history context in prompt
