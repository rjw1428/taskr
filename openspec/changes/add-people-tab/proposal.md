## Why

Currently there's no way to maintain relationship context or track conversation history. Users want to remember key details about people they care about and be reminded of what was discussed, so they can have more meaningful conversations and stay better connected.

## What Changes

- Add a new "People" tab (5th tab, right of Backlog) to the bottom navigation
- Ability to add people with minimal friction (name only, other details optional)
- Store personal information: name (required), age, birthday, job, spouse, and children with auto-aging
- Create conversation log entries with dates (defaulting to today), editable/deletable
- View people sorted by name or by most recent conversation
- Search people by name
- All data is private (Firebase security rules)

## Capabilities

### New Capabilities
- `people-management`: Create, view, edit, and delete people with personal information (name, age, birthday, job, spouse, children with auto-aging)
- `people-conversation-logs`: Create, view, edit, and delete conversation log entries with dates; display in reverse-chronological order

### Modified Capabilities
- `navigation`: Add People tab to bottom navigation bar (index 4)
- `routing`: Add People page route and navigation

## Impact

- New Firebase collection for people and conversation logs
- New UI screens and forms for people management
- Bottom navigation bar extends to 5 tabs
- Routing configuration adds new route
- New services for people CRUD operations
