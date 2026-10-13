#!/usr/bin/env bash
# Runs the Kotlin wet-ink unit tests: the model's (android/app/src/test/.../
# WetInkModelTest.kt, against the shared golden in src/test/resources), the
# flat ends', the prediction's and the incoming files' names, on a plain JVM, without Gradle. Run from
# app/:  tool/wet_ink_check/unit_test.sh   (LEN_NO_NIX=1: kotlinc, java from PATH)
set -euo pipefail
cd "$(dirname "$0")/../.."
. tool/wet_ink_check/env.sh
jars="${XDG_CACHE_HOME:-$HOME/.cache}/len/junit"
mkdir -p "$jars"
for j in junit/junit/4.13.2/junit-4.13.2.jar org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar; do
  [ -f "$jars/$(basename $j)" ] || curl -sfL "https://repo1.maven.org/maven2/$j" -o "$jars/$(basename $j)"
done
cp="$jars/junit-4.13.2.jar:$jars/hamcrest-core-1.3.jar"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
"${kotlin_cmd[@]}" "
  stdlib=\$(dirname \$(dirname \$(readlink -f \$(which kotlinc))))/lib/kotlin-stdlib.jar
  kotlinc -nowarn -cp '$cp' android/app/src/main/kotlin/dev/len/len/WetInkModel.kt \
    android/app/src/main/kotlin/dev/len/len/WetInkEnds.kt \
    android/app/src/main/kotlin/dev/len/len/WetInkPrediction.kt \
    android/app/src/main/kotlin/dev/len/len/IncomingNames.kt \
    android/app/src/test/kotlin/dev/len/len/WetInkModelTest.kt \
    android/app/src/test/kotlin/dev/len/len/WetInkEndsTest.kt \
    android/app/src/test/kotlin/dev/len/len/WetInkPredictionTest.kt \
    android/app/src/test/kotlin/dev/len/len/IncomingNamesTest.kt -d '$out' &&
  java -cp \"$out:$cp:android/app/src/test/resources:\$stdlib\" \
    org.junit.runner.JUnitCore dev.len.len.WetInkModelTest dev.len.len.WetInkEndsTest \
    dev.len.len.WetInkPredictionTest dev.len.len.IncomingNamesTest"
