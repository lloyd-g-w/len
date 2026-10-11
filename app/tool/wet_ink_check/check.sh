#!/usr/bin/env bash
# Checks that the Kotlin wet-ink model (WetInkOverlay's geometry) gives the
# same answers as the Dart model the Ink Lab measures. Run from app/:
#   tool/wet_ink_check/check.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
tool/light.sh nix develop ..# -c flutter test test/inklab/tools/wet_ink_vectors_test.dart \
  --dart-define=INKLAB_WET_VECTORS="$out" >/dev/null
tool/light.sh nix shell nixpkgs#kotlin -c bash -c "
  kotlinc -nowarn android/app/src/main/kotlin/dev/len/len/WetInkModel.kt \
    tool/wet_ink_check/Check.kt -include-runtime -d '$out/check.jar' &&
  java -cp '$out/check.jar' CheckKt '$out'/*.ev"
