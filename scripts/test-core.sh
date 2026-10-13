#!/usr/bin/env bash
# Run the DocuVaultCore test suite on macOS (no device, no signing). Prints a one-line summary last.
# PASS needs both: `swift test` exits 0, and the final "Executed N tests" line (the whole run) reports
# 0 failures. Every suite prints its own "Executed" line, so matching any one of them is not enough:
# that let a failing run print PASS (13 Oct).
set -uo pipefail
cd "$(dirname "$0")/../DocuVaultCore"
LOG=/tmp/docuvault-core-tests.log
swift test >"$LOG" 2>&1
status=$?
grep -E "error:|failed" "$LOG" | tail -n 20 || true
last=$(grep -E "Executed [0-9]+ tests?, with" "$LOG" | tail -n 1)
echo "$last"
if [ "$status" -eq 0 ] && echo "$last" | grep -q "with 0 failures"; then
  echo "CORE TESTS: PASS"
else
  echo "CORE TESTS: FAIL (see $LOG)"
  exit 1
fi
