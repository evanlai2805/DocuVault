# DocuVault — project memory for Claude Code

Personal iOS 26 app for Evan Lai (Singapore, restructuring analyst, works in English and Mandarin).
Document scanner with on-device OCR (en + zh-Hans + zh-Hant), a Face ID vault for identity and card
documents, on-device summaries, a fill-form keyboard, and an opt-in Claude cloud step with code-side
redaction. Not for the App Store. One user, one phone (iPhone 17 Pro).

Read `docs/HANDOFF.md` before any non-trivial task: it holds status, every decision Evan made at the
ten checkpoints, the open device-validation list, and the roadmap.

## How Evan works (follow this)

- Query, do not assume. If a request has two readings, ask one short question with lettered options.
- Big work goes in phases. Before building a phase, show a throwaway HTML mock in `docs/checkpoints/`
  (`checkpointN_<topic>.html`, same style as the existing ones) with numbered questions at the bottom.
  Build only after he answers. Small fixes and bug reports: just fix, no mock.
- Explanations to Evan: one idea per sentence, under ~20 words, active voice, one term per concept,
  lists for steps. Keep normal finance and legal vocabulary. Never apply this to Chinese text or to
  client-facing drafts.
- He cannot stand hallucinations. Verify against the code or docs before stating a fact. Say "I did not
  check" when you did not.
- Report work bottom-line first: what changed, what he must do, one next step. No recap of steps.

## Repo layout

```
project.yml              XcodeGen spec — the only source of truth for targets. Never edit .xcodeproj.
DocuVaultCore/           Swift package, tested on macOS with `swift test` (123 tests)
  Sources/DocuVaultCore/ Models, Checkers (MRZ, Luhn, NRIC, ChinaID, TextRules), Classify, Extract,
                         Vault (crypto, retention, export, fill formats), Summary, Cloud (Redactor, CloudGate)
  Sources/DocuVaultOCR/  Vision OCR, PDF import, image normaliser, title guesser (needs Apple frameworks)
DocuVault/               App target: App, Design (Theme), Storage (SwiftData), Capture, Review, Library,
                         Vault, Export, Settings, AI (Apple FM + MLX Qwen), Cloud (Claude opt-in)
DocuVaultKeyboard/       Keyboard extension; shares Storage/Models.swift, AppFiles.swift, Vault/VaultSession.swift
docs/                    design-system.md, HANDOFF.md, checkpoints/*.html
scripts/                 gen, test-core, build-sim, run-device, ci-status (use these; skills wrap them)
.github/workflows/       core-tests.yml, app-build.yml (macos-15, Xcode 26.3)
```

## Build and run

- Regenerate the project after any `project.yml` change or `git pull` that adds files: `scripts/gen.sh`.
- Core tests (fast, no device): `scripts/test-core.sh`. Run before every commit that touches `DocuVaultCore/`.
- Simulator build (compiles everything, no signing): `scripts/build-sim.sh`.
- Install on the phone: `scripts/run-device.sh`. Needs `.env.local` with `DOCUVAULT_TEAM_ID=<Apple team id>`
  (`.env.local` is git-ignored). The phone must be plugged in or on the same Wi-Fi, unlocked, Developer Mode on.
- CI status for the last push: `scripts/ci-status.sh`. GitHub Actions is the second opinion on every push.
- Toolchain: Xcode 26.3, Swift 6.2, iOS 26.0 deployment target. `SWIFT_STRICT_CONCURRENCY=complete`.
- MLX packages are pinned (`mlx-swift-lm` 3.31.x). Do not bump them without reading the note in `project.yml`.
- The Metal Toolchain must be installed in Xcode (Settings → Components) or MLX fails to build.

## Engineering rules (non-negotiable)

1. Anything a checksum can verify is verified in code, never by a model: MRZ check digits, Luhn,
   NRIC/FIN, PRC 身份证 ISO 7064. Every such rule has a test with a published specimen.
2. Vault documents never leave the phone. `CloudGate.allows` is the single gate; the UI must build no
   entry point for sensitive types, and `CloudService.send` must refuse too. Never add an "always allow".
3. Every cloud send goes through `CloudApprovalSheet` after `Redactor` has replaced IDs, contacts, names,
   amounts (and optionally dates) with placeholders. Placeholders are restored on the phone.
4. Encryption stays invisible to Evan: the UX is "locked notes behind Face ID". Keys live in the Keychain
   (`.biometryCurrentSet`, this device only). Never log or print field values.
5. English summaries follow STE (short sentences, active voice). Chinese summaries keep a conventional
   register. Summary language follows the document; mixed documents ask Evan which language.
6. Categories and labels display in English (Chinese label as a secondary line where it exists).
7. Design follows Flighty: SF Pro, bold titles, gradient stat cards, floating glass pills, light theme.
   Cards are coloured by state (green = checks pass, red = failed, graphite = nothing to check, navy =
   receipts/library, clay = cloud), never by document type. Tokens and components live in `DocuVault/Design/Theme.swift`
   and `docs/design-system.md`. Reuse them; do not invent new colours.
8. Swift 6 strict concurrency. `@MainActor @Observable` for app state. No `nonisolated(unsafe)` without a comment.
9. Keep `project.yml` versions in step: `CFBundleVersion` identical for app and keyboard targets.
10. Commit messages: imperative summary line, a short body saying what Evan decided when it applies.

## Conventions

- Field keys are camelCase strings shared by extractors, exporter, keyboard and redactor
  (`surname`, `passportNumber`, `nric`, `idNumber`, `pan`, `last4`, `merchant`, `total`, `partyA`…).
  Adding a field means updating `FillFormats.keys(for:)` if the keyboard should offer it.
- OCR confidence threshold is `OCRLine.lowConfidenceThreshold` (0.45). Vision's scale is coarse; do not "fix" by raising it.
- Export: `vault/<person>/<type>-<title>.md`, `vault/index.md`, `expenses.csv`. Markdown is the interchange
  format; the app mirror is always written, folder sync is optional.
- Tests live in `DocuVaultCore/Tests/`. OCR tests render text with CoreText (`TestImageFactory`).
- When Evan reports a bug with a screenshot, fix it, push, and tell him `git pull` then ⌘R. Do not ask him
  to describe what the screenshot shows unless the fix depends on it.
