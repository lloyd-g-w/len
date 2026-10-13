# Sourced by check.sh and unit_test.sh: how to run Flutter and the Kotlin
# compiler. Locally through nix (the dev shell; nixpkgs' kotlin and jdk);
# with LEN_NO_NIX=1 (CI) the flutter, kotlinc and java on PATH.
if [ -n "${LEN_NO_NIX:-}" ]; then
  flutter_cmd=(flutter)
  kotlin_cmd=(bash -c)
else
  flutter_cmd=(tool/light.sh nix develop ..# -c flutter)
  kotlin_cmd=(tool/light.sh nix shell nixpkgs#kotlin nixpkgs#jdk -c bash -c)
fi
