#!/usr/bin/env bash
# Runs a heavy command (Android/Gradle build, full test suite, release build)
# under a machine-wide lock so parallel worktrees never build at the same
# time — concurrent Gradle + Flutter builds exhausted RAM and crashed the host.
# Usage: app/tool/heavy.sh <command...>   (e.g. heavy.sh flutter build apk --debug)
set -euo pipefail
exec flock /tmp/len-heavy.lock nice -n 10 "$@"
