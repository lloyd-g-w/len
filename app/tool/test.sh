#!/usr/bin/env bash
# Runs a test tier fast: the test files bundled into shards
# (tool/test_shards.dart), so `flutter test` compiles a few dozen programs
# instead of one per file. Run from app/ (inside `nix develop`):
#   tool/test.sh            # default tier  (= flutter test -x slow)
#   tool/test.sh slow       # slow tier     (= flutter test -t slow)
#   tool/test.sh all        # both          (= flutter test)
#   tool/test.sh [tier] --record [flutter test args...]
# --record refreshes tool/test_times.json (balances the shards) from this run.
# Extra args go to `flutter test` (e.g. --plain-name, -r expanded).
# LEN_TEST_SHARDS (default 32) and LEN_TEST_JOBS (default: the cores, at
# most 16; at most 6 for slow and all) tune it. Single files still run as
# usual: flutter test test/x_test.dart
set -euo pipefail
cd "$(dirname "$0")/.."
tier=fast
case "${1:-}" in fast | slow | all) tier=$1 && shift ;; esac
record=
if [[ "${1:-}" == --record ]]; then record=1 && shift; fi
cores=$(nproc)
# The slow tier's benchmarks judge timings: at most 6 at a time there (as
# dart_test.yaml's concurrency), the default tier a file per core.
max=16
if [[ $tier != fast ]]; then max=6; fi
jobs=${LEN_TEST_JOBS:-$((cores < max ? cores : max))}
shards=${LEN_TEST_SHARDS:-32}
out=test/.shards/$tier
mapfile -t files < <(dart run tool/test_shards.dart generate "$tier" "$shards" "$out")
case $tier in
  fast) filter=(-x slow) ;;
  slow) filter=(-t slow) ;;
  all) filter=() ;;
esac
report=()
if [[ -n $record ]]; then report=(--file-reporter "json:$out/report.json"); fi
status=0
flutter test -j "$jobs" "${filter[@]}" "${report[@]}" "$@" "${files[@]}" || status=$?
if [[ -n $record ]]; then dart run tool/test_shards.dart record "$out/report.json"; fi
exit $status
