#!/usr/bin/env bash
# Run the DocuVaultCore test suite on macOS (no device, no signing). Prints a one-line summary last.
set -euo pipefail
cd "$(dirname "$0")/../DocuVaultCore"
swift test 2>&1 | tee /tmp/docuvault-core-tests.log | grep -E "error:|failed|Executed .* tests" || true
grep -E "Executed .* tests, with 0 failures" /tmp/docuvault-core-tests.log >/dev/null \
  && echo "CORE TESTS: PASS" || { echo "CORE TESTS: FAIL (see /tmp/docuvault-core-tests.log)"; exit 1; }
