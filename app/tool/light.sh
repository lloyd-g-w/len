#!/usr/bin/env bash
# Runs a small, targeted command (one or two test files) with a 4G memory
# cap and low priority, without the heavy lock. Full suites, the Ink Lab
# report and builds go through heavy.sh.
set -euo pipefail
exec systemd-run --user --scope -q -p MemoryMax="${LEN_LIGHT_MEM:-4G}" -p MemorySwapMax=0 -p CPUWeight=50 nice -n 10 "$@"
