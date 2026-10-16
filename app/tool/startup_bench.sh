#!/usr/bin/env bash
# Times launches of the Linux release bundle under a virtual display (see
# docs/PERFORMANCE.md, "Startup"):
#
#   tool/heavy.sh nix develop -c bash -c \
#     'cd app && flutter build linux --release --dart-define=LEN_STARTUP_TRACE=true'
#   LEN_STARTUP_LIBRARY=/tmp/lib/dev.len.len \
#     nix develop -c bash -c 'cd app && flutter test test/perf/startup_library_perf_test.dart'
#   tool/startup_bench.sh build/linux/x64/release/bundle/len /tmp/lib 7
#
# The second argument is an XDG_DATA_HOME to copy for every run ('-': a
# first launch). LEN_BENCH_SHOT=<png> screenshots the last run. Run from app/.
set -euo pipefail
[ $# -ge 2 ] || { sed -n '2,13p' "$0" >&2; exit 2; }
if ! command -v xvfb-run >/dev/null || ! command -v magick >/dev/null; then
  exec nix shell nixpkgs#xvfb-run nixpkgs#imagemagick nixpkgs#python3 -c "$0" "$@"
fi
# As in tool/e2e.sh: Nix's Flutter finds no system OpenGL; use Mesa.
mesa=$(nix build --no-link --print-out-paths nixpkgs#mesa)
glvnd=$(nix build --no-link --print-out-paths nixpkgs#libglvnd)
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$glvnd/lib:$mesa/lib"
export __EGL_VENDOR_LIBRARY_FILENAMES="$mesa/share/glvnd/egl_vendor.d/50_mesa.json"
export LIBGL_DRIVERS_PATH="$mesa/lib/dri"
xvfb-run -a -s '-screen 0 1600x1000x24' \
  python3 "$(dirname "$0")/startup_bench.py" "$(realpath "$1")" "$2" "${3:-5}"
