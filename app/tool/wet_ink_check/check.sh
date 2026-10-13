#!/usr/bin/env bash
# Checks that the Kotlin wet-ink model (WetInkOverlay's geometry) gives the
# same answers as the Dart model the Ink Lab measures. Run from app/:
#   tool/wet_ink_check/check.sh   (LEN_NO_NIX=1: flutter, kotlinc, java from PATH)
set -euo pipefail
cd "$(dirname "$0")/../.."
. tool/wet_ink_check/env.sh
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
"${flutter_cmd[@]}" test test/inklab/tools/wet_ink_vectors_test.dart \
  --dart-define=INKLAB_WET_VECTORS="$out" --dart-define=INKLAB_REAL=true >/dev/null
"${kotlin_cmd[@]}" "
  kotlinc -nowarn android/app/src/main/kotlin/dev/len/len/WetInkModel.kt \
    android/app/src/main/kotlin/dev/len/len/WetInkEnds.kt \
    tool/wet_ink_check/Check.kt -include-runtime -d '$out/check.jar' &&
  java -cp '$out/check.jar' CheckKt '$out'/*.ev"
