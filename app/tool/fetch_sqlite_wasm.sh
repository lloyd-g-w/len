#!/usr/bin/env bash
# Downloads web/sqlite3.wasm matching the `sqlite3` package version in
# pubspec.lock. Run after upgrading package:sqlite3 (the wasm module and
# the Dart bindings must come from the same release).
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(awk '/^  sqlite3:$/{f=1} f&&/version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)
url="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$version/sqlite3.wasm"
echo "Fetching $url"
curl -sSfL -o web/sqlite3.wasm "$url"
ls -l web/sqlite3.wasm
