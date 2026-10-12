---
name: checkpoint
description: Produce a throwaway HTML mock plus numbered questions before building a new DocuVault phase or any multi-screen feature. Use whenever a request adds screens or changes a flow; Evan reviews the mock before any code.
allowed-tools: Bash Read Write Glob
---
Evan decides from mocks, not prose. Before building a phase:

1. Read the latest `docs/checkpoints/checkpointN_*.html` and copy its `<style>` block and phone-frame markup
   so the new mock looks the same (SF Pro stack, gradient cards, pills, lavender hint banners).
2. Write `docs/checkpoints/checkpoint<N+1>_<topic>.html` with:
   - a one-paragraph intro and a flow strip (boxes → arrows) of the mechanism,
   - 3–6 phone frames showing the key states (empty, happy path, failure, locked/vault),
   - a "Rules that are code, not prompt" table when the feature touches privacy, checks, or the vault,
   - numbered questions `Q1…` at the bottom, each with a recommended default.
3. Open it for him: `open docs/checkpoints/<file>.html` (desktop app shows it inline when you send the path).
4. Stop. Build only after he answers. Record his answers in `docs/HANDOFF.md` §2 in the same commit as the build.

If the change is a bug fix or a one-screen tweak, skip this skill and just fix it.
