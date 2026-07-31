## Context

Taskr is a Flutter app using Provider for state, Firebase for persistence, and Material widgets. Styling today is essentially unmanaged: `theme.dart` sets `brightness: dark`, Roboto via `google_fonts`, and a placeholder `TextTheme` whose body styles are colored red/green/blue. Screens hardcode `Colors.white`/`Colors.black`, magic spacing numbers, and per-widget colors. The one deliberate, well-liked pattern is the color-coded task card (`task_item.dart` + `priorityColors` in `constants.dart`).

The redesign adopts a **"quiet depth"** direction (layered surfaces, soft elevation, one calm accent), **full light + dark** theming driven by the OS, **expressive motion** (reduced-motion aware), and a **refreshed-but-preserved** priority card. This is a visual/interaction refactor only — services, providers, models, routing, and Firebase are untouched.

Constraints:
- Must stay runnable at every step (broad surface area; incremental migration).
- Material 3 is the target so light/dark `ColorScheme` and component theming come for free.
- Motion must respect `MediaQuery.disableAnimations` / `MediaQuery.accessibleNavigation` (OS reduced-motion).
- Preserve all existing task-card behavior: complete, expand, reorder, multi-day connected radii, backlog vs. today, goal/recurring affordances.

## Goals / Non-Goals

**Goals:**
- A single design-token layer (color, type, spacing, radius, elevation, motion) that every screen consumes instead of inline literals.
- Cohesive light and dark themes that follow the system setting, built on Material 3 `ColorScheme`.
- A small library of reusable styled components (cards, section headers, buttons, inputs, empty states, sheets) so screens stop re-implementing chrome.
- Expressive, tasteful motion with a central set of durations/curves and a reduced-motion fallback.
- Harmonized priority palettes (light + dark) that keep the exact semantic mapping and card structure.
- Consistent application across all existing screens without changing behavior.

**Non-Goals:**
- No changes to business logic, data model, services, providers, routing structure, or Firebase.
- No new features or screens (People/Goals/etc. keep their current functionality).
- No user-facing theme toggle beyond following the OS (manual override can be a future change).
- Not chasing pixel-perfect parity with any external product; the direction is our own.

## Decisions

### D1: Material 3 with seeded light/dark `ColorScheme`
Adopt `useMaterial3: true` and build both themes from a token file. Base the schemes on explicit brand tokens (a charcoal-family neutral ramp + one calm accent), not a single `seedColor`, so the "quiet depth" surfaces and accent are intentional rather than algorithm-derived. Provide `theme`, `darkTheme`, and `themeMode: ThemeMode.system` to `MaterialApp`.
- **Alternative considered:** keep Material 2 and hand-roll colors → rejected; M3 gives light/dark component theming, `surfaceContainer` elevation tiers, and better defaults for free.
- **Alternative considered:** single `ColorScheme.fromSeed` → rejected; too much aesthetic control ceded to the seed algorithm for a design-led brief.

### D2: Tokens as plain Dart constants, exposed via `ThemeData` + a `ThemeExtension`
Define raw tokens (spacing scale, radii, elevation, motion durations/curves, and the priority palettes) as `const` values in a dedicated file (e.g. `lib/shared/design/tokens.dart`). Surface standard roles through `ThemeData`/`ColorScheme`/`TextTheme`; surface app-specific roles (priority colors, custom motion) through a `ThemeExtension<AppTokens>` so widgets read them via `Theme.of(context).extension<AppTokens>()!` and they adapt automatically to light/dark.
- **Rationale:** priority colors and motion are app concepts Material has no slot for; `ThemeExtension` is the idiomatic M3 way to add them without a global singleton and without breaking light/dark switching.
- **Alternative considered:** top-level global maps (today's `priorityColors`) → rejected; can't vary by brightness and bypasses `Theme`.

### D3: Typography via `google_fonts` with a real type scale
Replace the red/green/blue placeholder `TextTheme` with a deliberate scale. Pair a characterful display face (used with restraint for screen titles/large numbers) with a highly legible body/UI face, mapped onto M3 text roles (`displaySmall`, `titleLarge`, `bodyMedium`, `labelSmall`, etc.). Exact families chosen during implementation; both pulled through `google_fonts` (already a dependency).
- **Rationale:** the current scale is unusable (body text is literally colored); text color must come from `ColorScheme.onSurface`, not the style.

### D4: Centralized motion, reduced-motion aware
Create a motion helper (durations, curves, and a `bool reduceMotion(context)` derived from `MediaQuery`). All transitions read from it. Implement: staggered list entrances (Today/Backlog/People lists), shared-axis or hero transitions between tabs and pushed detail screens, micro-interactions (checkbox tick, card expand via `AnimatedSize`, FAB press), and a redesigned completion celebration that keeps `confetti` but pairs it with a card state animation. When reduced motion is on, transitions degrade to instant/opacity-only and celebration confetti is suppressed.
- **Alternative considered:** ad-hoc `AnimatedX` per widget with hardcoded durations → rejected; inconsistent feel and no reduced-motion story.
- **Dependency note:** prefer Flutter's built-in `animations` package (Material shared-axis/container-transform) over hand-built page routes; add it only if the built-in transitions are insufficient.

### D5: Priority card refresh preserves structure, retunes color
Keep `task_item.dart`'s layout, checkbox, expand, reorder handle, and multi-day connected `BorderRadius` logic. Move `priorityColors` off the global map into the `AppTokens` extension with **two** palettes (light + dark). Retune the muddy hues (maroon/mustard/forest) toward cleaner, cohesive tones that sit correctly on each brightness's surface, while keeping the high=red / medium=amber / low=green / info=neutral mapping. Ensure completed-state dimming and text contrast (WCAG AA for the title on each priority fill) hold in both modes.
- **Rationale:** this is the user's locked-in element; changing meaning or structure is out of scope, but color quality and light-mode legibility are the whole point.

### D6: Incremental migration, token layer first
Land tokens + themes + reusable components before touching screens, then migrate screen-by-screen so the app compiles and runs throughout. Screens that still use literals during migration simply look un-updated, not broken.

## Risks / Trade-offs

- **Broad surface area — many files hardcode `Colors.white`/`Colors.black`** → Migrate incrementally behind the token layer; prioritize the task list and shell (highest visibility), then remaining screens. Each screen is an independent, revertible step.
- **Light mode breaks assumptions baked into dark-only widgets** (e.g. white text on dark cards) → Route all text/icon color through `ColorScheme`/`AppTokens`; audit for literal colors as part of each screen's migration.
- **Priority-fill contrast in light mode** (dark text vs. light text on retuned fills) → Choose on-color per priority per brightness in tokens; verify AA contrast for the card title.
- **Expressive motion can feel gratuitous or hurt perceived performance** → Centralize durations/curves, keep them short, and honor reduced-motion; the frontend-design principle "spend boldness in one place" means the completion celebration is the signature moment, everything else stays subtle.
- **`ThemeExtension` + `lerp` for smooth light/dark transitions** adds boilerplate → Acceptable; it's the idiomatic cost of app-specific themed tokens.
- **Regressing task-card behavior during the refactor** → Treat card behavior as a contract (see `task-card-visuals` spec); manually verify complete/expand/reorder/multi-day after the card migration.

## Migration Plan

1. Add `design/tokens.dart` (spacing, radius, elevation, motion, light+dark priority palettes) and the `AppTokens` `ThemeExtension`.
2. Rewrite `theme.dart` into `lightTheme` + `darkTheme` (M3, real type scale, `AppTokens` attached); wire `MaterialApp` with `themeMode: system`.
3. Add reusable components under `lib/shared/design/` (styled card, section header, primary/secondary buttons, input decoration, empty state, bottom-sheet shell) and the motion helper.
4. Migrate the shell (`home.dart`: app bar, bottom nav, FABs) + add tab/page transitions.
5. Migrate the task card (`task_item.dart`) and task-list screens; verify behavior contract.
6. Migrate remaining screens (People, Goals, Performance, Accomplishments, Login, Settings, About) to tokens/components.
7. Pass for reduced-motion and light/dark verification across screens.

**Rollback:** purely presentational; revert per-commit (each screen migrates independently) or revert the whole branch. No data or API migration, so rollback is safe at any point.

## Open Questions

- Exact display/body typeface pairing (decided during implementation against the "quiet depth" direction).
- Final accent hue (teal vs. indigo family) and the neutral ramp values — to be set in tokens and eyeballed on-device in both modes.
- Whether the built-in `animations` package is needed or Flutter's stock transitions suffice.
- ~~Whether a manual in-app light/dark override is wanted later~~ — RESOLVED: added a System/Light/Dark selector in Settings backed by a `ThemeProvider` (ChangeNotifier) that drives `MaterialApp.themeMode`. Defaults to System. Persisted per-user in Firestore at `todos/{uid}/settings/preferences` (no native plugin — `shared_preferences` was avoided because its Android build hits a JdkImageTransform/jlink failure under this project's AGP 8.1.1 + compileSdk 36).
