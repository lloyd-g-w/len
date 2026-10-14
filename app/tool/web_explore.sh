#!/usr/bin/env bash
# Runs tool/web_explore.py on a web build (default build/web) with Playwright,
# Chromium, Firefox and Xvfb from nixpkgs. Build first: tool/build_web.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
# Playwright finds its Firefox in the environment's root (the browsers
# package's directories are linked there).
exec nix shell --impure --expr 'with import (builtins.getFlake "nixpkgs") {};
  buildEnv { name = "len-web-explore"; paths = [ (python3.withPackages (p: [ p.playwright ]))
    chromium xvfb-run playwright-driver.browsers ]; }' \
  -c bash -c 'export PLAYWRIGHT_BROWSERS_PATH; PLAYWRIGHT_BROWSERS_PATH=$(dirname "$(dirname "$(command -v python3)")")
    exec python3 tool/web_explore.py "$@"' web_explore "${@:-build/web}"
