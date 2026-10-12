---
name: ci
description: Check GitHub Actions for the latest push (core tests + Simulator build) and read its annotations. Use after every push, or when Evan asks whether CI is green.
allowed-tools: Bash Read
---
Run `scripts/ci-status.sh`. Both workflows must be `success` for the newest commit:
`DocuVaultCore tests` and `DocuVault app build (iOS Simulator)`.

- Runs take 6–10 minutes (MLX compile). If `in_progress`, say so and check again later rather than polling every minute.
- Annotations carry the compiler errors and the test count ("Executed N tests, with 0 failures").
- Log and artifact downloads are fine from a Mac; `gh run view <id> --log-failed` shows the failing step.
- Never mark work done while CI is red for the commit you pushed.
