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

# --pwa-strategy=none stops the bootstrap from registering a service worker, so
# nothing new is cached, and it leaves an empty flutter_service_worker.js in
# build/web. Clients that loaded an older build still hold a registration for
# that URL, so overwrite the empty file with the kill switch, which unregisters
# itself and clears their caches. See tool/sw-kill-switch.js for why neither
# deleting the file nor the empty one Flutter emits does the job.
cp tool/sw-kill-switch.js build/web/flutter_service_worker.js

# Give each font a content-hashed URL so browsers still holding a font cached
# as immutable fetch the current one. See tool/bust-font-cache.mjs.
node tool/bust-font-cache.mjs build/web

# The predeploy hook in firebase/firebase.json copies build/web into
# firebase/public, so no manual copy here.
cd firebase
if [[ "${1:-}" == "--preview" ]]; then
  firebase hosting:channel:deploy preview
else
  firebase deploy --only hosting
fi
