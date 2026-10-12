---
name: test
description: Run the DocuVaultCore test suite (checkers, extractors, vault crypto, summaries, redactor). Use before every commit that touches DocuVaultCore, and when Evan reports a misread or a wrong field.
allowed-tools: Bash Read Grep Edit
---
Run `scripts/test-core.sh` from the repo root.

- `CORE TESTS: PASS` → say the count and move on.
- Failures → the log is at `/tmp/docuvault-core-tests.log`. Fix the code, not the expectation, unless the
  test encodes a decision Evan has since changed (check `docs/HANDOFF.md` §2).

When a real document was misread on the phone:
1. Reproduce in a test first: add a case to the matching test file in `DocuVaultCore/Tests/DocuVaultCoreTests/`
   using the OCR lines Evan pasted (never a photo of a real ID in the repo).
2. Make it pass in the rule, keeping published specimens green (ICAO 9303 passport, 身份证 sample).
3. Run the whole suite, then `/build`.
