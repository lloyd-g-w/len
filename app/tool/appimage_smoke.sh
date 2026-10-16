#!/usr/bin/env bash
# Smoke test of a Len AppImage under a virtual display: starts it with the
# given files / links (a fresh data directory, no FUSE: extract-and-run),
# waits, takes a screenshot of the display and fails if Len exited or
# logged an error.
#
#   tool/appimage_smoke.sh <Len.AppImage> [files or len:// links…]
#
# Run from app/ (inside `nix develop` for a Nix-built bundle: see README's
# NixOS note). Takes xvfb-run, Mesa and ImageMagick from nixpkgs when Nix is
# available. The screenshot and the log go to $LEN_SMOKE_OUT (default
# /tmp/len-appimage-smoke); LEN_SMOKE_WAIT sets the seconds to wait (20).
set -euo pipefail
[ $# -ge 1 ] || { sed -n '2,12p' "$0" >&2; exit 2; }

if ! command -v xvfb-run >/dev/null || ! command -v magick >/dev/null; then
  command -v nix >/dev/null || { echo "smoke: needs xvfb-run and ImageMagick" >&2; exit 2; }
  exec nix shell nixpkgs#xvfb-run nixpkgs#imagemagick -c "$0" "$@"
fi
if command -v nix >/dev/null; then
  # As in tool/e2e.sh: Nix's Flutter finds no system OpenGL; use Mesa.
  mesa=$(nix build --no-link --print-out-paths nixpkgs#mesa)
  glvnd=$(nix build --no-link --print-out-paths nixpkgs#libglvnd)
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$glvnd/lib:$mesa/lib"
  export __EGL_VENDOR_LIBRARY_FILENAMES="$mesa/share/glvnd/egl_vendor.d/50_mesa.json"
  export LIBGL_DRIVERS_PATH="$mesa/lib/dri"
fi

image=$(realpath "$1")
shift
out="${LEN_SMOKE_OUT:-/tmp/len-appimage-smoke}"
wait_s="${LEN_SMOKE_WAIT:-20}"
data=$(mktemp -d /tmp/len-smoke-data.XXXXXX)
trap 'rm -rf "$data"' EXIT
mkdir -p "$out"

# A display Xvfb picks itself where xvfb-run can (-d; -a races other jobs
# for a number and may share, then lose, another job's display).
xvfb_display=-a
[[ $(xvfb-run --help 2>&1) == *--auto-display* ]] && xvfb_display=-d

# One shell inside the virtual display: Len in the background, then the
# screenshot while it runs.
XDG_DATA_HOME="$data" XDG_CONFIG_HOME="$data/config" XDG_CACHE_HOME="$data/cache" \
APPIMAGE_EXTRACT_AND_RUN=1 TMPDIR="$data" \
  xvfb-run "$xvfb_display" -s '-screen 0 1600x1000x24' bash -c '
    "$0" "${@:3}" >"$1/len.log" 2>&1 &
    pid=$!
    sleep "$2"
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"; echo "smoke: Len exited early (status $?)" >&2; exit 1
    fi
    magick import -window root "$1/screen.png"
    kill "$pid"; wait "$pid" 2>/dev/null || true
  ' "$image" "$out" "$wait_s" "$@"

if grep -nE 'EXCEPTION CAUGHT|Unhandled [Ee]xception|\[ERROR:' "$out/len.log"; then
  echo "smoke: Len logged errors (above); log in $out/len.log" >&2
  exit 1
fi
echo "smoke: ran ${wait_s}s; screenshot $out/screen.png, log $out/len.log"
