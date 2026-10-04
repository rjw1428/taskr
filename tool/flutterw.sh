#!/usr/bin/env bash
# Wraps `flutter run|build ...`, stamping the current git commit into the app
# (shown on the About screen). The version itself comes from pubspec.yaml at
# build time via package_info_plus.
set -euo pipefail
cd "$(dirname "$0")/.."
commit="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
git diff --quiet HEAD 2>/dev/null || commit="$commit-dirty"
exec flutter "$1" "${@:2}" --dart-define=GIT_COMMIT="$commit"
