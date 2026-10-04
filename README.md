# taskr

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


Running local environment:
`rps run`
- Build-time config comes from `.env` via `--dart-define-from-file=.env` on
  every `flutter run` / `flutter build`. It holds only public identifiers
  (OAuth client IDs, Algolia search key). Gemini is called through the
  `callGemini` Cloud Function (secret `GEMINI_API_KEY`), and the parking API
  is called with the signed-in user's Firebase ID token.
- This will run emulators
- Run `docker compose up --build` to get started
- If you need to run outside the container, From firebase directory, to run emulators locally
`firebase emulators:start --project=taskr-1428 --import ./emulator/data --export-on-exit`


Deploying the web build (Firebase Hosting):
- `flutter build web --release --dart-define-from-file=.env`, then from the
  `firebase` directory `firebase deploy --only hosting`. A predeploy hook
  copies `build/web` into `firebase/public` (gitignored) because Hosting only
  serves from inside the `firebase` directory. The site root has an SPA
  rewrite to `index.html`.
- The Flutter entry points (`index.html`, `flutter_bootstrap.js`,
  `flutter_service_worker.js`, `main.dart.js`, `version.json`) are served
  with no-cache headers so browsers pick up a new build instead of a stale
  service worker. Other static assets are cached for a year.
- Preview before going live: `firebase hosting:channel:deploy preview` from
  `firebase` gives a temporary shareable URL.
- The default `taskr-1428.web.app` / `.firebaseapp.com` domains are already
  authorized for Google sign-in. If you attach a custom domain under Hosting
  in the console, also add it under Authentication > Settings > Authorized
  domains.

Generating Data Models:
`flutter pub run build_runner build`