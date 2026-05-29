## Context

Taskr is a Flutter app backed by Firebase (Firestore, Cloud Functions, FCM, VertexAI). Tasks are stored at `todos/{userId}/tasks/{date}/items/{taskId}` with date-based partitioning. The app already has recurring task generation (via RRule), VertexAI integration (`gemini-1.5-flash` for coaching feedback), and Cloud Functions for scheduled jobs. A placeholder `/goals` route and "Add a goal" FAB exist in the home screen.

The goals feature introduces a new entity type that bridges the gap between aspirational objectives and the existing daily task system by using an LLM to decompose goals into weekly task batches.

## Goals / Non-Goals

**Goals:**
- Users can create, view, edit, and delete personal goals with configurable timeframe and frequency
- An LLM generates a week's worth of concrete tasks from each goal, informed by prior task completion history
- Goal tasks appear in the user's normal daily task list with clear goal attribution
- Users receive push reminders at 5 PM and 9 PM for incomplete goal tasks
- A weekly Cloud Function regenerates tasks for active goals automatically
- Goals can be fully managed (edited/deleted) from any linked task

**Non-Goals:**
- Social/shared goals or accountability partners
- Goal templates or a curated goal library
- Granular progress metrics or analytics dashboards (beyond task completion tracking)
- Real-time LLM interaction (chat with the AI about your goal) — generation is batch-only
- Timezone-aware scheduling (use device timezone via Cloud Function user metadata, but no multi-timezone support)

## Decisions

### 1. Goal data model — flat subcollection under user

Store goals at `todos/{userId}/goals/{goalId}`.

```
Goal {
  id: string
  title: string
  description: string?
  timeframe: enum (1_week, 1_month, 3_months, 6_months, 1_year)
  frequency: enum (daily, n_times_week, auto)
  frequencyCount: int?          // only when frequency = n_times_week
  startDate: string (YYYY-MM-DD)
  endDate: string (YYYY-MM-DD)  // computed from startDate + timeframe
  status: enum (active, completed, deleted)
  createdAt: timestamp
  modifiedAt: timestamp
}
```

**Why flat subcollection**: Consistent with existing patterns (`todos/{userId}/recurring/`, `todos/{userId}/feedback/`). Goals are few per user (likely <20 active), so a single collection query is efficient.

**Alternative considered**: Embedding goals inside a user profile document. Rejected because goals have their own lifecycle and sub-resources (generation history), and document size limits could become a concern.

### 2. Task generation history — subcollection under goal

Store generation history at `todos/{userId}/goals/{goalId}/generations/{generationId}`.

```
Generation {
  id: string
  generatedAt: timestamp
  weekStart: string (YYYY-MM-DD)
  weekEnd: string (YYYY-MM-DD)
  taskIds: string[]             // references to generated task IDs
  prompt: string                // the prompt sent to the LLM
  response: string              // raw LLM response (for debugging)
  completedTaskIds: string[]    // backfilled as tasks are completed
  skippedTaskIds: string[]      // tasks that expired without completion
}
```

**Why store prompt/response**: Enables debugging, prompt iteration, and provides full context to the next generation cycle without re-querying all historical tasks.

**Alternative considered**: Storing only task IDs and re-deriving history from tasks. Rejected because querying across date-partitioned task collections is expensive and fragile.

### 3. Linking tasks to goals — `goalId` field on Task model

Add an optional `goalId: string?` field to the existing Task model. Goal-generated tasks are inserted into the normal `todos/{userId}/tasks/{date}/items/{taskId}` collection.

**Why reuse existing task infrastructure**: Goal tasks benefit from all existing features — reordering, push/reschedule, completion tracking, performance stats, daily views. No parallel task system needed.

**Alternative considered**: A separate `goalTasks` collection. Rejected because it would require duplicating task UI, ordering, and completion logic.

### 4. LLM task generation — VertexAI with structured prompting

Use the existing `FirebaseVertexAI` integration with `gemini-1.5-flash`. The prompt includes:
- Goal title and description
- Timeframe and frequency settings
- History summary: completed tasks (with dates), skipped tasks, any user notes
- Current week number relative to goal start
- Instruction to return JSON array of tasks with: title, description, suggested day (relative to week), estimated effort

The LLM response is parsed as JSON. Each task object is converted to a Task and written to the appropriate date partition.

**Why structured JSON output**: Eliminates ambiguous parsing. The model is instructed to return a specific schema, and we validate before writing.

**Why gemini-1.5-flash**: Already in use, fast, cost-effective for structured generation. Upgrade path to gemini-2.0 is trivial since we use the Firebase SDK.

### 5. Weekly regeneration — Cloud Function on schedule

A new Cloud Function `generateGoalTasks` runs weekly (Sunday evening) via `onSchedule("every sunday 20:00")`.

Flow:
1. Query all users who have at least one active goal
2. For each user, for each active goal where `endDate > now`:
   a. Fetch the most recent generation record
   b. Cross-reference `taskIds` against actual task documents to determine completed vs. skipped
   c. Build the LLM prompt with history context
   d. Call VertexAI, parse response
   e. Write tasks to appropriate date partitions for the coming week
   f. Write a new generation record

**Why Sunday evening**: Tasks are ready when users start their week Monday. The 8 PM slot avoids conflict with the daily reminder functions.

**Alternative considered**: Client-side generation triggered on app open. Rejected because it's unreliable (user might not open the app), creates race conditions, and burns mobile device resources.

### 6. Initial task generation — triggered on goal creation

When a user creates a goal, the first batch of tasks is generated immediately on the client side using the existing `AiService`. This provides instant feedback rather than making the user wait until the next Sunday cycle.

**Why client-side for initial generation**: Immediate UX feedback. The user creates a goal and sees tasks appear. Subsequent weekly generations happen server-side.

### 7. Reminder notifications — scheduled Cloud Function

A new Cloud Function `goalTaskReminders` runs twice daily via two scheduled triggers:
- `goalReminder5pm`: `onSchedule("every day 17:00")`
- `goalReminder9pm`: `onSchedule("every day 21:00")`

Flow:
1. Query all users with active goals
2. For each user, query today's tasks where `goalId != null` and `completed == false`
3. If incomplete goal tasks exist, send FCM notification with task count and goal name
4. Skip if user has no FCM token

**Why two separate functions vs. one with delay**: Simpler, stateless, no need for Cloud Tasks or delayed execution. Each function is a clean check-and-notify.

**Alternative considered**: Client-side local notifications. Rejected because they don't fire reliably when the app is killed, and we already have the Cloud Function + FCM pattern established.

### 8. Goal management from task context — bottom sheet action

When viewing a task that has a `goalId`, the task's popup menu gains a "View Goal" action. This navigates to a goal detail page showing:
- Goal title, description, timeframe, frequency
- Progress summary (weeks elapsed, tasks completed vs. total)
- Edit and Delete actions
- Delete cascades: sets goal status to `deleted`, deletes all future (uncompleted) tasks with this `goalId`

**Why popup menu action**: Consistent with existing task actions (EDIT, REMOVE, VIEW_SERIES). Low-friction discovery.

### 9. Goal form UI — modal bottom sheet

Follow the existing `AddTaskScreen` pattern: a modal bottom sheet with form fields for title, description, timeframe picker, and frequency picker. Timeframe and frequency use segmented button controls for quick selection.

### 10. Flutter state management — extend existing Provider pattern

Add a `GoalService` (ChangeNotifier) following the same pattern as `TagProvider` and `TaskService`. Stream goals from Firestore with real-time listeners.

## Risks / Trade-offs

**[LLM output quality varies]** → Validate JSON schema before writing tasks. If parsing fails, retry once with a stricter prompt. If still failing, log the error in the generation record and skip that week (user can manually trigger regeneration from the goal detail page).

**[VertexAI rate limits / costs at scale]** → Goals are generated weekly, not on every app open. Even with 1000 users × 5 goals each, that's 5000 LLM calls per week — well within free-tier VertexAI limits. Monitor via Cloud Function logs.

**[Querying tasks by goalId across date partitions is expensive]** → For cascade delete and history building, we store `taskIds` in the generation record rather than querying across partitions. The generation record is the source of truth for which tasks belong to a goal.

**[Timezone mismatch for reminders]** → Cloud Functions run in a fixed timezone. Store user's timezone preference in their profile doc and adjust reminder scheduling. V1 can assume a single timezone (US Eastern) with a note to expand later.

**[Goal edit after tasks are generated]** → Editing a goal's title/description takes effect on the next generation cycle. Editing timeframe/frequency recalculates `endDate` and adjusts the next generation. Already-generated tasks for the current week are not modified.

## Resolved Questions

1. **Manual mid-week regeneration**: Yes. A "Regenerate" button on the goal detail page replaces remaining uncompleted tasks for the current week with a fresh LLM batch. No per-week limit — trust the user.
2. **Performance score integration**: Yes, naturally. Goal tasks are regular tasks with a `goalId` — they flow through the existing performance scoring system unchanged. No separate goal-specific metrics.
3. **Goal expiry behavior**: Auto-complete with summary. When `endDate` passes, the goal is marked completed and the user sees a summary of what was accomplished (tasks completed, weeks active, completion rate). The summary is shown in-app on the goal detail page.
