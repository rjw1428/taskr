## ADDED Requirements

### Requirement: Series creation completes in a single batched write

Creating a recurring task series SHALL write the template and all in-horizon occurrences in one Firestore `WriteBatch`. The "Add task" form SHALL close as soon as that commit is acknowledged, and its latency SHALL NOT scale with the length of the series.

Batches SHALL be chunked at 400 operations to stay below Firestore's 500-operation limit.

#### Scenario: Long series closes the form promptly

- **WHEN** a user saves a task recurring every 3 weeks for one year
- **THEN** the template and every occurrence within the horizon are committed in one batch
- **AND** the form closes once that commit is acknowledged
- **AND** no per-occurrence sequential writes are issued

#### Scenario: Form-close latency is independent of series length

- **WHEN** a user saves a daily series and a yearly series with the same start date
- **THEN** both forms close after the same number of round trips

#### Scenario: Series exceeding the batch limit is chunked

- **WHEN** materializing a series whose occurrences require more than 400 batch operations
- **THEN** the writes are split across multiple batches of at most 400 operations each

### Requirement: No unguarded Firestore await on the form-close path

Every Firestore operation awaited before the "Add task" form closes SHALL be wrapped in `ackWrite` or otherwise bounded by a timeout. A stalled or absent connection SHALL surface as a queued-write notice and close the form, never as an indefinitely open dialog.

#### Scenario: Template write stalls with no connectivity

- **WHEN** a user saves a recurring series while the device cannot reach the server
- **THEN** the write is bounded by the `ackWrite` timeout
- **AND** the user is shown the queued-write notice
- **AND** the form closes rather than remaining on its spinner

#### Scenario: Write is acknowledged normally

- **WHEN** a user saves a recurring series while online
- **THEN** the commit is acknowledged and the form closes without a queued-write notice

### Requirement: Occurrences are materialized on a bounded rolling horizon

A series SHALL materialize only those occurrences falling within `[seriesStart, today + 60 days]`, bounded by the template's end date. The template SHALL record `lastMaterializedDate` as its watermark.

#### Scenario: Year-long series materializes only the horizon

- **WHEN** a user creates a daily series ending one year from today
- **THEN** only occurrences up to 60 days ahead are written
- **AND** `lastMaterializedDate` is set to the last date materialized

#### Scenario: Series shorter than the horizon materializes fully

- **WHEN** a user creates a weekly series ending in 3 weeks
- **THEN** every occurrence in the series is materialized
- **AND** `lastMaterializedDate` is set to the final occurrence's date

### Requirement: The first occurrence is always materialized

Series creation SHALL always write at least the first occurrence, even when the series begins beyond the materialization horizon, so that saving is always visibly confirmed.

#### Scenario: Series starting beyond the horizon

- **WHEN** a user creates a series whose first occurrence is 6 months from today
- **THEN** that first occurrence is written as a task document
- **AND** the user is not left with a saved series and no visible task

### Requirement: Active series are topped up on a rolling basis

A top-up pass SHALL extend each active series to `today + 60 days`. It SHALL run once per app launch, triggered when the root `userStream` resolves an authenticated user, and SHALL be guarded against concurrent re-entry within the process.

#### Scenario: Horizon extends after time passes

- **WHEN** the app launches 30 days after a year-long daily series was created
- **THEN** occurrences are materialized forward to 60 days from that launch date
- **AND** `lastMaterializedDate` advances accordingly

#### Scenario: Re-entry is prevented

- **WHEN** a top-up pass for a series is already running in this process
- **THEN** a second pass for the same series returns without issuing writes

#### Scenario: Series past its end date is left alone

- **WHEN** the top-up pass encounters a series whose end date has passed
- **THEN** no occurrences are materialized for it

### Requirement: Materialization is idempotent

The top-up pass SHALL treat a collection-group query on `(userId, recurringTemplateId)` as the authority on which occurrences already exist, so that a null, stale, or incorrect `lastMaterializedDate` can never produce duplicates.

Where that query is unavailable — for example the composite index is not yet deployed and the query fails with `failed-precondition` — the pass SHALL degrade gracefully by falling back to the watermark alone rather than failing.

#### Scenario: Series created before this change is topped up

- **WHEN** the top-up pass runs against a series that has no `lastMaterializedDate`
- **THEN** dates that already have an occurrence are skipped
- **AND** no duplicate occurrences are created

#### Scenario: Index not yet deployed

- **WHEN** the collection-group query fails with `failed-precondition`
- **THEN** the pass falls back to watermark-only deduplication
- **AND** series creation and top-up continue to function

#### Scenario: Repeated passes converge

- **WHEN** the top-up pass runs twice in succession for the same series
- **THEN** the second pass writes no new occurrences

### Requirement: Recurring reminders are configured as a time of day

When recurrence is enabled, the task form SHALL offer a time-only reminder control rather than the date-and-time picker used for one-off tasks. The chosen time SHALL be stored on the template as `reminderTimeOfDay` in local `HH:mm` form.

#### Scenario: Recurring form shows a time-only control

- **WHEN** a user enables recurrence and then enables a reminder
- **THEN** the control asks only for a time of day
- **AND** no date picker is presented

#### Scenario: One-off form is unchanged

- **WHEN** a user enables a reminder on a task that is not recurring
- **THEN** the existing date-and-time picker is presented

### Requirement: Each occurrence carries its own absolute reminder instant

Materialization SHALL expand `reminderTimeOfDay` against each occurrence's own local date, writing the result to the occurrence's existing `reminderTime` field as an absolute UTC timestamp, within the same batch as the occurrence itself. This expansion SHALL add no additional round trips.

#### Scenario: Reminder lands at the configured local time on each date

- **WHEN** a series is created with a reminder time of 08:30
- **THEN** every materialized occurrence carries a `reminderTime` resolving to 08:30 local on its own due date

#### Scenario: Occurrences spanning a DST boundary

- **WHEN** a series with a reminder time of 08:30 has occurrences on both sides of a daylight-saving transition
- **THEN** each occurrence's `reminderTime` resolves to 08:30 local on its own date
- **AND** the stored UTC instants differ by the offset change

### Requirement: Reminders are enqueued by the top-up pass

The top-up pass SHALL enqueue delivery for occurrences due within 30 days that have a `reminderTime` and no `reminderTaskName`, using the existing `scheduleReminder` callable, and SHALL write the returned task name back to the occurrence.

The pass SHALL enqueue at most 10 reminders per run; remaining work SHALL converge on subsequent launches. The 30-day window reflects the Cloud Tasks `scheduleTime` ceiling.

#### Scenario: Reminders inside the window are enqueued

- **WHEN** the top-up pass finds occurrences due in the next 30 days with a reminder and no task name
- **THEN** delivery is scheduled for each
- **AND** the returned task name is written to the occurrence

#### Scenario: Reminders beyond the Cloud Tasks ceiling are deferred

- **WHEN** an occurrence with a reminder is due more than 30 days out
- **THEN** no delivery is scheduled on this pass
- **AND** the occurrence retains its `reminderTime` for a later pass to enqueue

#### Scenario: Already-enqueued reminders are not re-enqueued

- **WHEN** the pass encounters an occurrence that already has a `reminderTaskName`
- **THEN** no additional delivery is scheduled for it

#### Scenario: Per-pass cap converges across launches

- **WHEN** a daily series has more than 10 un-enqueued reminders inside the window
- **THEN** at most 10 are enqueued on this pass
- **AND** the remainder are enqueued on subsequent launches

### Requirement: Deferred reminder scheduling is surfaced at creation

When a newly created series has more in-window reminders than a single pass can enqueue, the user SHALL be shown a neutral notice at creation time indicating that reminder scheduling is still in progress.

The launch-time top-up pass SHALL NOT show this notice; it SHALL record the deferral in debug output only, so that opening the app does not produce an unexplained notice the user cannot act on.

#### Scenario: Long daily series is created

- **WHEN** a user creates a daily series whose in-window reminders exceed the per-pass cap
- **THEN** a neutral notice is shown indicating reminder scheduling is still in progress

#### Scenario: Short series is created

- **WHEN** a user creates a series whose in-window reminders fit within the per-pass cap
- **THEN** no deferral notice is shown

#### Scenario: Launch-time deferral is silent

- **WHEN** the launch-time top-up pass defers reminder enqueueing because of the cap
- **THEN** the deferral is recorded in debug output
- **AND** no notice is shown to the user

### Requirement: Pushing an occurrence carries its series reminder forward

When a pushed task belongs to a series whose template defines a `reminderTimeOfDay`, the push SHALL cancel the existing scheduled delivery and re-derive `reminderTime` against the task's new date, so the reminder follows the task rather than being lost.

Tasks with no series template, series with no reminder time, and occurrences whose template no longer exists SHALL retain the existing behavior of clearing the reminder.

#### Scenario: Series occurrence with a reminder is pushed

- **WHEN** a user pushes an occurrence of a series whose reminder time is 08:30
- **THEN** the previously scheduled delivery is cancelled
- **AND** the task's `reminderTime` resolves to 08:30 local on its new due date

#### Scenario: Pushed reminder is scheduled for delivery

- **WHEN** a pushed occurrence's re-derived reminder falls inside the enqueue window
- **THEN** delivery is scheduled for the new instant

#### Scenario: One-off task is pushed

- **WHEN** a user pushes a task that has no `recurringTemplateId`
- **THEN** the existing behavior applies and the reminder is cleared

#### Scenario: Series has no reminder time

- **WHEN** a user pushes an occurrence of a series whose template defines no `reminderTimeOfDay`
- **THEN** the reminder is cleared as before

#### Scenario: Template no longer exists

- **WHEN** a user pushes an occurrence whose series template has been deleted
- **THEN** re-derivation is skipped and the reminder is cleared
- **AND** the push completes successfully

#### Scenario: Interrupted pass resumes

- **WHEN** a top-up pass fails partway through enqueueing
- **THEN** occurrences left without a `reminderTaskName` are enqueued on the next pass

### Requirement: An imminent reminder is enqueued at creation time

When a newly created series has a first occurrence whose reminder falls due before the next top-up pass would reasonably run, creation SHALL enqueue that single reminder inline, so a same-day reminder is not missed.

#### Scenario: Same-day series with a reminder later today

- **WHEN** a user creates a series starting today with a reminder time later today
- **THEN** that occurrence's reminder is enqueued as part of creation

#### Scenario: First reminder is not imminent

- **WHEN** the first occurrence's reminder is days away
- **THEN** creation enqueues nothing inline and leaves it to the top-up pass

### Requirement: Deleting a series scales with occurrence count, not series length

Deleting a series SHALL locate its occurrences with a single collection-group query on `(userId, recurringTemplateId)` rather than querying date by date. It SHALL cancel any enqueued reminders for the occurrences it removes, delete outstanding future occurrences, preserve completed occurrences as history, and delete the template.

#### Scenario: Year-long series is deleted

- **WHEN** a user deletes a year-long daily series
- **THEN** its occurrences are located in a single collection-group query
- **AND** no per-date query is issued for each date in the series

#### Scenario: Enqueued reminders are cancelled

- **WHEN** deleting a series whose occurrences carry `reminderTaskName` values
- **THEN** each corresponding scheduled delivery is cancelled

#### Scenario: Completed occurrences are preserved

- **WHEN** a series with both completed and outstanding occurrences is deleted
- **THEN** completed occurrences remain
- **AND** outstanding occurrences are removed

#### Scenario: Index not yet deployed

- **WHEN** the collection-group query is unavailable
- **THEN** deletion falls back to the per-date scan and still removes the series

### Requirement: Editing a series re-materializes on the same horizon

Editing a series SHALL cancel enqueued reminders for future occurrences, remove outstanding future occurrences, and re-materialize using the same bounded horizon and batched write as creation, resetting `lastMaterializedDate`. Creation and editing SHALL NOT use different horizons.

#### Scenario: Cadence is changed

- **WHEN** a user changes a series from weekly to every 3 weeks
- **THEN** outstanding future occurrences on the old cadence are removed
- **AND** occurrences on the new cadence are materialized across the same horizon creation would use

#### Scenario: Reminder time is changed

- **WHEN** a user changes a series' reminder time of day
- **THEN** already-enqueued deliveries for future occurrences are cancelled
- **AND** future occurrences carry a `reminderTime` derived from the new time of day

#### Scenario: Completed occurrences survive an edit

- **WHEN** a series with completed occurrences is edited
- **THEN** those completed occurrences remain unchanged

### Requirement: All occurrences in a series receive identical field treatment

Every materialized occurrence SHALL carry the same task fields derived from the series definition. No field SHALL be applied to the first occurrence but omitted from the rest.

#### Scenario: Countdown applies across the series

- **WHEN** a user creates a series with the countdown option enabled
- **THEN** every materialized occurrence carries the countdown setting, not only the first

#### Scenario: Tags apply across the series

- **WHEN** a user creates a series with tags selected
- **THEN** every materialized occurrence carries those tags

### Requirement: Ordering of the visible day is preserved

The first occurrence SHALL be inserted into its day's `taskOrder` using the standard ordering rules. Later occurrences, which land on future days, SHALL be appended via `arrayUnion`, which is equivalent to ordered insertion on an empty day.

#### Scenario: First occurrence is slotted correctly

- **WHEN** a series' first occurrence lands on a day that already contains tasks
- **THEN** it is placed according to the standard ordering rules rather than appended

#### Scenario: Future occurrences on empty days

- **WHEN** later occurrences land on days with no existing tasks
- **THEN** each day's `taskOrder` contains that occurrence
- **AND** no read is issued to compute the ordering
