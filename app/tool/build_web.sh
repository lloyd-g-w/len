#!/usr/bin/env bash
# Release web build with offline support: `flutter build web` with every
# resource served from the app's own origin (CanvasKit included, so the
# installed app needs no CDN), then the service worker's precache list.
# Extra arguments go to `flutter build web` (e.g. --wasm, --base-href /len/).
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn "$@"
dart run tool/web_precache.dart build/web
