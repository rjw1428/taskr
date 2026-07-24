# Implementation Tasks: Add People Tab

## 1. Data Model & Persistence Layer

- [x] 1.1 Create Person model class (name, age, birthday, job, spouse, kids array, logs array, timestamps)
- [x] 1.2 Create Kid model class (name, age, birthday, dateAdded)
- [x] 1.3 Create ConversationLog model class (id, date, entry text, createdAt, updatedAt)
- [x] 1.4 Add JSON serialization support to all models (json_annotation)
- [x] 1.5 Create PeopleService with Firebase Firestore operations:
  - [x] 1.5a addPerson(Person) → Future<String> (returns personId)
  - [x] 1.5b updatePerson(String personId, Person) → Future<void>
  - [x] 1.5c deletePerson(String personId) → Future<void>
  - [x] 1.5d getPeople() → Stream<List<Person>> (all people for current user)
  - [x] 1.5e getPerson(String personId) → Stream<Person>
  - [x] 1.5f addLog(String personId, ConversationLog) → Future<void>
  - [x] 1.5g updateLog(String personId, String logId, ConversationLog) → Future<void>
  - [x] 1.5h deleteLog(String personId, String logId) → Future<void>
- [x] 1.6 Firebase security rules — stored under todos/{userId}/people, covered by the existing todos/{userId}/{document=**} rule (no new rule needed)

## 2. State Management

- [x] 2.1 Create PeopleProvider class extending ChangeNotifier
- [x] 2.2 Add methods to PeopleProvider:
  - [x] 2.2a fetchPeople() (calls PeopleService.getPeople)
  - [x] 2.2b addPerson(Person)
  - [x] 2.2c updatePerson(Person)
  - [x] 2.2d deletePerson(personId)
  - [x] 2.2e addLog(personId, logEntry)
  - [x] 2.2f updateLog(personId, logId, logEntry)
  - [x] 2.2g deleteLog(personId, logId)
- [x] 2.3 Add PeopleProvider to MultiProvider in main.dart

## 3. Routing & Navigation

- [x] 3.1 Create PeoplePage widget (main list screen)
- [x] 3.2 Add '/people' route to routeConfig in routing.dart with icon and index 4
- [x] 3.3 Update home.dart to handle People tab FAB (no FAB needed for MVP, or simple add person FAB)
- [x] 3.4 Test bottom navigation bar displays all 5 tabs correctly

## 4. People List View

- [x] 4.1 Build PeoplePage UI with:
  - [x] 4.1a Search bar at top (filters by name)
  - [x] 4.1b Sort toggle (Name / Last Updated)
  - [x] 4.1c ListView showing people in sorted order
  - [x] 4.1d Tap person to navigate to detail view
  - [x] 4.1e Empty state message when no people
- [x] 4.2 Implement search functionality (case-insensitive name matching)
- [x] 4.3 Implement sort logic:
  - [x] 4.3a Sort by name (alphabetical)
  - [x] 4.3b Sort by lastUpdated (most recent first)
- [x] 4.4 Add floating action button to create new person

## 5. Add/Edit Person Form

- [x] 5.1 Create PersonFormPage with:
  - [x] 5.1a Name field (required)
  - [x] 5.1b Age field (optional, number)
  - [x] 5.1c Birthday field (optional, date picker)
  - [x] 5.1d Job field (optional, text)
  - [x] 5.1e Spouse field (optional, text)
  - [x] 5.1f Kids section (add/remove kids with name, age, birthday)
- [x] 5.2 Implement form validation (name required)
- [x] 5.3 Implement kids management:
  - [x] 5.3a Add kid button adds new kid to list
  - [x] 5.3b Each kid has name, age, birthday fields
  - [x] 5.3c Each kid can be removed
  - [x] 5.3d Auto-age calculation (show in UI: if birthday provided, use that; else use anniversary of dateAdded)
- [x] 5.4 Handle save (calls PeopleProvider.addPerson or updatePerson)
- [x] 5.5 Handle cancel (pop without saving)

## 6. Person Detail View

- [x] 6.1 Create PersonDetailPage with:
  - [x] 6.1a Sticky header displaying person's static info (name, age, birthday, job, spouse, kids with ages)
  - [x] 6.1b Only show fields that are populated (no empty placeholders)
  - [x] 6.1c Edit button in header (navigates to PersonFormPage)
  - [x] 6.1d Delete button with confirmation dialog
  - [x] 6.1e "Add Log Entry" button
- [x] 6.2 Below header, display conversation logs:
  - [x] 6.2a List of logs in reverse chronological order (most recent first)
  - [x] 6.2b Each log shows date and full entry text
  - [x] 6.2c Tap log to edit or delete
- [x] 6.3 Implement auto-aging for kids in display:
  - [x] 6.3a If birthday provided, calculate age from current date
  - [x] 6.3b If no birthday, increment age on anniversary of dateAdded
  - [x] 6.3c Display current calculated age in person detail header

## 7. Add/Edit Conversation Log

- [x] 7.1 Create AddLogPage with:
  - [x] 7.1a Multi-line text field for log entry
  - [x] 7.1b Date picker defaulting to today
  - [x] 7.1c Save and cancel buttons
- [x] 7.2 Create EditLogPage (reuse AddLogPage logic with pre-filled values)
- [x] 7.3 Implement log entry modal/bottom sheet (alternative to page)
- [x] 7.4 Handle save (calls PeopleProvider.addLog or updateLog)
- [x] 7.5 Implement delete log:
  - [x] 7.5a Delete button on log entry
  - [x] 7.5b Confirmation dialog
  - [x] 7.5c Calls PeopleProvider.deleteLog

## 8. Testing & Edge Cases

- [x] 8.1 Test adding person with name only
- [x] 8.2 Test adding person with all fields
- [x] 8.3 Test kids auto-aging (with and without birthday)
- [x] 8.4 Test editing person (all fields)
- [x] 8.5 Test deleting person (with confirmation)
- [x] 8.6 Test adding multiple log entries for same person
- [x] 8.7 Test editing log entries (text and date)
- [x] 8.8 Test deleting log entries
- [x] 8.9 Test search by name
- [x] 8.10 Test sort by name and sort by last updated
- [x] 8.11 Test empty people list
- [x] 8.12 Test navigation between tabs
- [x] 8.13 Test data persistence across app restart

## 9. Polish & Finalize

- [x] 9.1 Review UI/UX consistency with existing tabs
- [x] 9.2 Add appropriate icons and colors
- [x] 9.3 Handle loading states (while fetching people)
- [x] 9.4 Handle error states (Firebase errors)
- [x] 9.5 Test on device (iOS/Android)
