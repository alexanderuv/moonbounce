#!/usr/bin/env bash
# Runs `swift test` with the given arguments, and fails unless Swift Testing
# reports at least one test. A run that discovers no tests otherwise passes,
# as Windows release builds do (see docs/validation.md, Platforms).
set -euo pipefail

log=$(mktemp)
swift test "$@" 2>&1 | tee "$log"

# Strip color codes, then require "Test run with N tests" with N > 0.
if ! sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -Eq 'Test run with [1-9][0-9]* tests?'; then
    echo "::error::swift test $* ran no Swift Testing tests"
    exit 1
fi
