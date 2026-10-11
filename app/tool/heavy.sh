#!/usr/bin/env bash
# Runs a heavy command (Android/Gradle build, full test suite, release build)
# safely on a shared dev machine:
#  * a machine-wide lock, so parallel worktrees never build at the same time;
#  * a hard memory cap (cgroup via systemd-run, when available), so a runaway
#    build is killed instead of exhausting RAM and freezing the host;
#  * lower CPU priority.
# Usage: app/tool/heavy.sh <command...>   (e.g. heavy.sh flutter build apk --debug)
# LEN_HEAVY_MEM overrides the cap (default 12G).
set -euo pipefail
mem="${LEN_HEAVY_MEM:-12G}"
if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope -q true 2>/dev/null; then
  exec flock /tmp/len-heavy.lock systemd-run --user --scope -q \
    -p MemoryMax="$mem" -p MemorySwapMax=0 -p CPUWeight=50 \
    nice -n 10 "$@"
fi
exec flock /tmp/len-heavy.lock nice -n 10 "$@"
