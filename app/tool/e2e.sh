#!/usr/bin/env bash
# End-to-end tests of the real Linux app (integration_test/, see README
# "Develop"): real SQLite, files, plugins and rendering under a virtual X
# display, against a real sync server (server/) with a throwaway database.
#
#   1. device_a_test   first launch → notebook, ink, text, image, PDF export,
#                      canvas, search, trash, sync up        (data dir A)
#   2. device_b_test   a second device syncs it down, adds a stroke (data dir B)
#   3. relaunch_test   device A restarted: everything persisted, B's stroke
#                      syncs in                               (data dir A)
#
# Run from app/ inside the dev shell (on a shared machine through
# tool/heavy.sh: it builds the Linux app). Needs xvfb-run and Mesa (taken
# from nixpkgs when Nix is available) and curl. Fails on any test failure
# and on uncaught errors in the logs. Pictures of each step and the logs go
# to $LEN_E2E_OUT (default: a fresh directory under /tmp, printed at the end).
# Extra arguments go to every `flutter test` (e.g. --plain-name).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xvfb-run >/dev/null; then
  command -v nix >/dev/null || { echo "e2e: needs xvfb-run" >&2; exit 2; }
  exec nix shell nixpkgs#xvfb-run -c "$0" "$@"
fi
if command -v nix >/dev/null; then
  # Nix's Flutter finds no system OpenGL: use Mesa's software renderer.
  mesa=$(nix build --no-link --print-out-paths nixpkgs#mesa)
  glvnd=$(nix build --no-link --print-out-paths nixpkgs#libglvnd)
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$glvnd/lib:$mesa/lib"
  export __EGL_VENDOR_LIBRARY_FILENAMES="$mesa/share/glvnd/egl_vendor.d/50_mesa.json"
  export LIBGL_DRIVERS_PATH="$mesa/lib/dri"
fi

work=$(mktemp -d /tmp/len-e2e.XXXXXX)
out="${LEN_E2E_OUT:-$work/out}"
mkdir -p "$out"
server_pid=
cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$work/a" "$work/b" "$work/server"
  # Put pubspec back as it was (see below).
  if [ -f "$work/pubspec.yaml" ]; then
    cp "$work/pubspec.yaml" pubspec.yaml && cp "$work/pubspec.lock" pubspec.lock
    flutter pub get >/dev/null || true
  fi
}
trap cleanup EXIT

# integration_test is not a dependency of the app: with it, Android builds
# fail under Nix (Gradle can't configure its project in the read-only
# store). Add it for this run only; cleanup() restores pubspec.
cp pubspec.yaml pubspec.lock "$work/"
flutter pub add 'dev:integration_test:{"sdk":"flutter"}' >/dev/null

# --- The sync server, on a free port with a temporary database. -----------
port=$((20000 + RANDOM % 20000))
token=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
mkdir -p "$work/server"
(cd ../server && dart pub get >/dev/null)
(cd ../server && LEN_SYNC_TOKEN="$token" LEN_DB_PATH="$work/server/len.db" HOST=127.0.0.1 \
  PORT="$port" exec dart run bin/server.dart) >"$out/server.log" 2>&1 &
server_pid=$!
url="http://127.0.0.1:$port"
for _ in $(seq 1 180); do  # dart run builds native assets the first time
  curl -fsS "$url/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "$url/v1/health" >/dev/null || { cat "$out/server.log"; exit 1; }

# --- The phases: each one a fresh app process. ----------------------------
phase() { # <test file> <data dir>
  local name=$1 data=$2 log="$out/$1.log" status=0
  mkdir -p "$data"
  echo "e2e: $name ($data)"
  XDG_DATA_HOME="$data" XDG_CONFIG_HOME="$data/config" XDG_CACHE_HOME="$data/cache" \
    xvfb-run -a -s '-screen 0 1600x1000x24' \
    flutter test "integration_test/$name.dart" -d linux \
    --dart-define=E2E_SERVER="$url" --dart-define=E2E_TOKEN="$token" \
    --dart-define=E2E_OUT="$out" "${@:3}" 2>&1 | tee "$log" || status=$?
  # Errors the tests cannot see (native side, other isolates, after the end).
  if grep -nE 'EXCEPTION CAUGHT|Unhandled [Ee]xception|PlatformDispatcher error|\[ERROR:' "$log"; then
    echo "e2e: $name logged errors (above)" >&2
    status=1
  fi
  [ "$status" -eq 0 ] || { echo "e2e: $name failed; logs in $out" >&2; exit "$status"; }
}

# LEN_E2E_PHASES="a" runs only the first phase (while working on it).
phases="${LEN_E2E_PHASES:-a b relaunch}"
[[ " $phases " == *" a "* ]] && phase device_a_test "$work/a" "$@"
[[ " $phases " == *" b "* ]] && phase device_b_test "$work/b" "$@"
[[ " $phases " == *" relaunch "* ]] && phase relaunch_test "$work/a" "$@"
# The server stops cleanly (as on `docker stop`).
kill -TERM "$server_pid"
server_status=0
wait "$server_pid" || server_status=$?
server_pid=
if [ "$server_status" -ne 0 ] || grep -n 'Unhandled exception' "$out/server.log"; then
  echo "e2e: the sync server failed (exit $server_status); see $out/server.log" >&2
  exit 1
fi
echo "e2e: all passed; pictures and logs in $out"
