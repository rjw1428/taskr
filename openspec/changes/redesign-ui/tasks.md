# Implementation Tasks: Redesign UI

## 1. Token Layer

- [x] 1.1 Create `lib/shared/design/tokens.dart` with spacing scale, corner-radius, and elevation constants
- [x] 1.2 Add motion tokens (named durations + curves) to the token layer
- [x] 1.3 Define the neutral surface ramp + calm accent for both light and dark
- [x] 1.4 Define light and dark priority palettes (high/medium/low/info) with matching on-colors, retuned from the current maroon/mustard/forest hues
- [x] 1.5 Create `AppTokens` `ThemeExtension` exposing priority palettes and motion tokens, with `copyWith`/`lerp`
- [x] 1.6 Add a `reduceMotion(BuildContext)` helper derived from `MediaQuery`

## 2. Themes

- [x] 2.1 Rewrite `lib/theme.dart`: build `lightTheme` and `darkTheme` on Material 3 from the tokens
- [x] 2.2 Replace the placeholder red/green/blue `TextTheme` with a real type scale (display + body faces via `google_fonts`) mapped to M3 text roles
- [x] 2.3 Attach `AppTokens` to both themes
- [x] 2.4 Wire `MaterialApp` with `theme`, `darkTheme`, and `themeMode: ThemeMode.system` in `main.dart`
- [ ] 2.5 Verify runtime light/dark switching follows the OS setting

## 3. Reusable Components

- [x] 3.1 Build a shared surface/card container component
- [x] 3.2 Build a section-header component
- [x] 3.3 Build primary and secondary button components
- [x] 3.4 Build a shared text input decoration
- [x] 3.5 Build a shared empty-state component
- [x] 3.6 Build a shared bottom-sheet shell
- [x] 3.7 Add motion helpers/wrappers (staggered list entrance, shared-axis/fade transition, animated expand)

## 4. Navigation Shell

- [x] 4.1 Restyle the app bar in `home.dart` using themed colors/type
- [x] 4.2 Restyle the bottom navigation bar with clear selected/unselected states from tokens
- [x] 4.3 Restyle the floating action button(s); preserve per-tab create actions and the long-press add-divider affordance
- [x] 4.4 Add animated tab switching (shared-axis/fade) respecting reduced motion
- [x] 4.5 Add animated transitions for pushed detail screens

## 5. Task Card (signature element)

- [x] 5.1 Migrate `task_item.dart` to read priority colors from `AppTokens` (remove reliance on the global `priorityColors` map)
- [x] 5.2 Route all card text/icon colors through the color scheme (remove hardcoded white/black)
- [x] 5.3 Apply refined chrome (elevation, radius, border, spacing) per "quiet depth"
- [x] 5.4 Preserve multi-day connected corner-radius logic
- [x] 5.5 Animate tap-to-expand (description/tags) with the motion tokens
- [x] 5.6 Redesign the completion interaction (card state animation + celebration), suppressed under reduced motion
- [ ] 5.7 Verify card behavior contract: complete, expand, reorder, overflow menu, goal/recurring indicators, backlog vs. today
- [ ] 5.8 Verify priority-title contrast (WCAG AA) in both light and dark

## 6. Screen Migration

- [x] 6.1 Migrate the task-list screens (`task_list/`) to tokens/components + staggered list entrance
- [x] 6.2 Migrate the People screens (`people/`)
- [x] 6.3 Migrate the Goals screens (`goals/`)
- [x] 6.4 Migrate the Performance screens (`performance/`) including chart colors
- [x] 6.5 Migrate the Accomplishments screens (`accomplishments/`)
- [x] 6.6 Migrate the Login / Create-account screens (`login/`)
- [x] 6.7 Migrate Settings and About screens
- [x] 6.8 Migrate shared widgets (`shared/loading.dart`, `shared/error.dart`, `shared/progress_bar.dart`)

## 7. Verification & Polish

- [x] 7.1 Audit for remaining hardcoded `Colors.white`/`Colors.black`/magic literals across migrated screens
- [ ] 7.2 Verify every screen in both light and dark mode on device
- [ ] 7.3 Verify reduced-motion setting degrades all animations and suppresses celebration
- [ ] 7.4 Confirm no behavioral regressions (services/providers/routing untouched); run the app through core flows
- [ ] 7.5 Final "remove one accessory" pass — cut any decoration not serving the direction

## 8. Theme Override (added mid-implementation)

- [x] 8.1 Persist the chosen `ThemeMode` (Firestore `todos/{uid}/settings/preferences`; `shared_preferences` avoided due to an Android jlink build failure)
- [x] 8.2 Create `ThemeProvider` (ChangeNotifier) that loads/persists the chosen `ThemeMode`
- [x] 8.3 Register `ThemeProvider` and drive `MaterialApp.themeMode` from it (default System)
- [x] 8.4 Add a System / Light / Dark selector to the Settings screen
- [ ] 8.5 Verify override switches instantly and persists across restart (device)
