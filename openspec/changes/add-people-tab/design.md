## Context

Currently, taskr is structured around task management with tabs for today's tasks, performance, goals, and backlog. To support relationship management, we're adding a new People tab that functions as a lightweight CRM for maintaining conversation context with ~50 relationships.

Key architectural patterns already in place:
- Bottom navigation with route-based tab switching (see `routing.dart`)
- Firebase Firestore for persistent data (see `task.service.dart`)
- Provider pattern for state management (see `accomplishment.provider.dart`)
- Consistent CRUD services structure

## Goals / Non-Goals

**Goals:**
- Add People tab as a new first-class section in the app
- Enable users to store and maintain relationship context efficiently
- Support free-form conversation logging with temporal ordering
- Auto-age children based on birthday or anniversary of entry date
- Private by default (Firebase security rules)

**Non-Goals:**
- Birthday/anniversary reminders (future feature)
- Nudges to reach out (future feature)
- Integration with contacts or social media
- Email/SMS/phone call shortcuts
- Encryption beyond Firebase security rules

## Decisions

### Data Model: Person as Log + Static Info
**Decision:** Store each person as a document with both static fields (name, age, job, etc.) and an array of conversation log entries.

**Rationale:** Conversation logs are the primary user interaction; static fields are reference context. Nesting logs in the person document avoids join complexity and keeps related data together.

**Alternatives considered:**
- Separate collections for People and ConversationLogs with foreign keys → more normalized but requires joins; logs are subordinate data, not independent queries
- Firestore subcollection (people/{personId}/logs) → could help with query pagination if logs became large; not necessary for MVP

### Kids Auto-Aging Strategy
**Decision:** If birthday provided, calculate age from birthday. If not, increment age on the anniversary of `dateAdded`.

**Rationale:** Provides flexibility: users can add birthdays later if they want real dates, but ages still increment automatically without them. Simple to implement and understand.

### Firebase Collection Structure
Stored under the existing `todos/{userId}` root so the already-deployed
`match /todos/{userId}/{document=**}` security rule applies (no separate rule
deploy needed).
```
/todos/{userId}/people/{personId}
  - name: string
  - age: number | null
  - birthday: string (ISO) | null
  - job: string | null
  - spouse: string | null
  - kids: [
      {name, age, birthday, dateAdded}
    ]
  - logs: [
      {id, date (ISO), entry, createdAt, updatedAt}
    ]
  - createdAt: timestamp
  - lastUpdated: timestamp (for sorting by "last entered")
```

Security rule: covered by the existing `todos/{userId}/{document=**}` rule — only readable/writable by the authenticated user.

### UI Navigation
Add People as index 4 in `routeConfig` after Backlog. Bottom nav extends to 5 items.

### Service Layer
Create `PeopleService` following the pattern of `TaskService` and `GoalService`:
- `addPerson(Person)`
- `updatePerson(Person)`
- `deletePerson(personId)`
- `getPeople()` → Stream of all people for user
- `addLog(personId, logEntry)`
- `updateLog(personId, logId, logEntry)`
- `deleteLog(personId, logId)`

### State Management
Use Provider pattern with `ChangeNotifierProvider<PeopleProvider>` similar to existing providers.

## Risks / Trade-offs

**Risk: Firebase Firestore cost with many logs**
→ Mitigation: At MVP, document structure is fine. If logs grow large (>1000 per person), consider subcollection migration. Current cost should be negligible for 50 people × 10-50 logs each.

**Risk: Kids auto-aging on anniversary of `dateAdded` feels artificial**
→ Mitigation: This is explicitly temporary until user provides a birthday. Clear UI messaging helps.

**Risk: Free-form log entries lack structure**
→ Mitigation: User requested free-form. Future could add tags/categories. MVP prioritizes simplicity.

## Migration Plan

1. Add `people_management` and `people_conversation_logs` specs
2. Create `PeopleService` and `PeopleProvider`
3. Add route `/people` and People UI screens
4. Update `routeConfig` and bottom navigation
5. Add Firebase collection rules
6. No migration of existing data needed (new feature)
7. Deploy without feature flag (visible immediately to all users)

## Open Questions

- Should there be a "favorites" or "pinned" feature to surface key relationships? (Deferring to future)
- Is name-only search sufficient, or search within log entries? (Proposal specifies name-only for MVP)
- Should there be a bulk import/export feature? (Out of scope for MVP)
