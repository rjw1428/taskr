## Why

Taskr's UI was built to be functional, not polished: `theme.dart` is a near-empty dark theme with a placeholder text scale (body styles literally set to red/green/blue), there is no shared design language, and every screen re-implements its own spacing, colors, and typography inline. The app works but does not feel considered or delightful. This change establishes a real design system and applies it across the app to make Taskr feel sleek, cohesive, and alive — while preserving the one thing that already works: the color-coded, structured task cards.

## What Changes

- Introduce a **design system** — a single source of truth for color (light + dark), typography, spacing, elevation/surfaces, corner radii, and motion primitives — replacing ad-hoc inline styling.
- Adopt a **"quiet depth"** visual direction: layered charcoal (dark) and warm-neutral (light) surfaces, soft elevation and subtle translucency, and one calm accent color (teal/indigo family).
- Add **full light + dark theming** driven by the OS setting (today the app is dark-only). **BREAKING** for the current hardcoded-dark assumption in widgets that use literal `Colors.white`/`Colors.black`.
- Restyle the **navigation shell** — app bar, bottom navigation, and floating action buttons — and add polished **page/tab transitions**.
- Introduce **expressive, lively motion** — staggered list reveals, hero/shared transitions between screens, micro-interactions (checkbox, card expand, FAB press), and a redesigned task-completion celebration — all gated behind the OS reduced-motion setting.
- **Refresh the color-coded priority cards**: keep the exact semantic mapping (high = red, medium = amber, low = green, info = neutral) and the existing card structure/behavior, but retune the shades to be cleaner and cohesive with the new palette, and add light-mode variants that read well on a light background.
- Apply the system consistently across all existing screens (Today, Performance, Goals, Backlog, People, and their forms/modals). This is a visual/interaction refactor; no business logic or data model changes.

## Capabilities

### New Capabilities
- `design-system`: The foundational token and theming layer — color roles (light + dark), typography scale, spacing/radius/elevation tokens, motion primitives (durations, curves, reduced-motion handling), and the shared styled components every screen consumes.
- `app-navigation-shell`: The app's chrome and navigation — themed app bar, bottom navigation bar, per-context action button(s), and animated transitions between tabs and pushed screens.
- `task-card-visuals`: The signature color-coded task card — preserved structure and semantics with harmonized priority palettes (light + dark), refined chrome (elevation, radius, borders), and completion/expand micro-interactions.

### Modified Capabilities
<!-- No existing OpenSpec specs to modify; this is the first design-focused change. -->

## Impact

- **New:** `lib/theme.dart` becomes a full theming module (light + dark `ThemeData`, token definitions); likely new files under `lib/shared/` for design tokens, motion helpers, and reusable styled widgets.
- **Modified (visual only):** `lib/shared/constants.dart` (`priorityColors` retuned + light/dark variants), `lib/home/home.dart` (shell/nav/FAB), `lib/task_list/task_item.dart` and other `task_list/` widgets, and the presentation layers of `people/`, `goals/`, `performance/`, `accomplishments/`, `login/`, `settings/`, and `about/`.
- **Behavioral compatibility:** No changes to services, providers, models, routing structure, or Firebase. Task-card interactions (complete, expand, reorder, multi-day rendering) are preserved.
- **Dependencies:** May add a light-weight animation/util dependency if needed; `google_fonts`, `confetti`, and `font_awesome_flutter` are already available. Requires touching many widgets that currently hardcode `Colors.white`/`Colors.black`.
- **Risk:** Broad surface area. Mitigated by landing the token layer first, then migrating screen-by-screen so the app stays runnable throughout.
