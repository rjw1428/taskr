# Testing this app

## Harness

`test/helpers/harness.dart` replaces every platform boundary with a fake:

```dart
import 'helpers/harness.dart';   // from test/<file>_test.dart

late TestEnv env;
setUp(() async => env = await TestEnv.create());   // uid 'u1', signed in
tearDown(() => env.dispose());
```

`TestEnv` gives you:

| Member | What it is |
|---|---|
| `env.db` | `FakeFirebaseFirestore`, wired into `FirebaseRefs.firestore`, so every service and screen reads and writes it |
| `env.col('tasks')` | shortcut for `db.collection('todos').doc(uid).collection('tasks')` |
| `env.userDoc()` | the `todos/{uid}` document data |
| `env.auth` | `MockFirebaseAuth`; `AuthService().user` resolves from it |
| `env.functions['name'] = (payload) => ...` | handler for a Cloud Functions callable; `env.functionCalls` records every call |
| `env.push` | `FakePushGateway`: token, permission count, and stream controllers for onMessage / onMessageOpenedApp / onTokenRefresh |
| `env.google` | `FakeGoogleSignIn`: per-profile results and a call log |
| `FlutterLocalNotificationsPlatform.instance as FakeLocalNotifications` | records `show` / `cancel` calls |
| `WorkmanagerPlatform.instance as FakeWorkmanager` | records registered tasks |

`TestEnv.create(signedIn: false)` gives a signed-out session. `env: {'KEY': 'v'}` adds dotenv values.

Mount screens with `pumpApp(tester, widget, wrapInScaffold: true)` for anything that in production lives inside a Scaffold body (tabs, list screens, forms shown in bottom sheets). It installs the same providers and theme as production and the `scaffoldMessengerKey` that error snackbars use.

Use `settle(tester)` rather than `pumpAndSettle`: several screens show an indeterminate progress indicator or a looping animation, and `pumpAndSettle` never returns on those.

## Seeding data

Prefer the service API over raw documents so the stored shape stays honest:

```dart
final tasks = TaskService();                    // resolves to env.db automatically
final id = await tasks.addTask(Task(added: 1, title: 'Buy milk', dueDate: '2026-09-19'));
```

When you must write raw documents, copy the field names from `lib/services/models.g.dart`. Task rows live at `todos/{uid}/tasks/{yyyy-MM-dd}/items/{id}` with the day's order in `todos/{uid}/tasks/{date}.taskOrder`.

The day shown by the task list comes from `DateService().setSelectedDate(...)`; set it before pumping so the test does not depend on the wall clock.

## Network calls

HTTP-backed services (Gemini in `ai.service.dart` and `goal.service.dart`, Google Calendar in `calendar.service.dart`, the parking service) expose a mutable endpoint you can point at a local `HttpServer`. `test/parking_service_test.dart` has the pattern. `GoalService.llm` can replace the whole model call.

## Measuring coverage

Write coverage to your own path so parallel runs do not clobber each other:

```
flutter test --coverage --coverage-path=/tmp/mycov/lcov.info test/my_test.dart
awk '/^SF:/{f=$0; sub("SF:lib/","",f)} /^LF:/{lf=substr($0,4)} /^LH:/{lh=substr($0,4); printf "%5.1f%%  %4d/%-4d %s\n", (lf>0?100*lh/lf:0), lh, lf, f}' /tmp/mycov/lcov.info | grep <file>
```

Lines that are never hit are listed as `DA:<line>,0` under the file's `SF:` block.

## Ground rules for new tests

- One test file per screen or service, named `<subject>_test.dart`.
- Assert behavior a user or caller would notice: what is on screen, what was written to Firestore, which callable ran. Do not assert on private widget structure.
- Cover the branches, not just the happy path: empty state, error state, signed-out, the cancel path of every dialog.
- Every test must pass in isolation and with the whole suite (`flutter test`).
