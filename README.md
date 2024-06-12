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
- Currently the .env file is read to see if PROD mode is true or false
- This will run emulators
- Run `docker compose up --build` to get started
- If you need to run outside the container, From firebase directory, to run emulators locally
`firebase emulators:start --project=taskr-1428 --import ./emulator/data --export-on-exit`