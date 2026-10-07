#!/usr/bin/env bash
# Build the Flutter web app and deploy it to Firebase Hosting.
# Usage: ./deploy-web.sh [--preview]
#   --preview  deploy to a temporary preview channel instead of the live site
set -euo pipefail

# Always run from the repo root, wherever the script is invoked from.
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "error: .env not found in $(pwd) — the web build needs --dart-define-from-file=.env" >&2
  exit 1
fi

flutter build web --release --pwa-strategy=none --dart-define-from-file=.env

# --pwa-strategy=none stops the bootstrap from registering a service worker, but
# a previous build may have left the script behind in build/web. Drop it so the
# URL 404s: a browser still holding an old registration unregisters on that.
rm -f build/web/flutter_service_worker.js

# The predeploy hook in firebase/firebase.json copies build/web into
# firebase/public, so no manual copy here.
cd firebase
if [[ "${1:-}" == "--preview" ]]; then
  firebase hosting:channel:deploy preview
else
  firebase deploy --only hosting
fi
