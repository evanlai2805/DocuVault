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

## Bug reports by screenshot

- Evan tests on the phone and drops screenshots into `Unresolved Issues Screenshots/` (git-ignored, local
  only). He will not describe the bugs in words.
- "Fix all bugs", "fix the bugs", or anything like it means: read every image in that folder and treat them
  as the complete bug list for this round.
- **Be certain before you fix.** A screenshot often shows several things that could be wrong, or shows
  intended behaviour that only looks wrong. If you are unsure what the bug is, or unsure whether the issues
  you spotted are the ones he wants fixed, ask. State per screenshot what you think you see, then one short
  question with lettered options. Keep asking until there is no doubt left. A wrong fix costs far more than
  the question, and guessing here is the same as hallucinating.
- Once certain: fix, run `scripts/test-core.sh`, push, and tell him `git pull` then ⌘R.
- Then move that screenshot into `Resolved Issues Screenshots/` (also git-ignored), so the unresolved
  folder always holds exactly the outstanding bugs. If he reports the bug is still there, move it back.

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

## Writing and symbols (applies to app UI, docs and mocks)

- **No emoji anywhere.** Not in the app UI, not in checkpoint mocks, not in docs. Icons are SF Symbols
  (`Image(systemName:)`). A mock that stands in for the UI uses the same restraint, because Evan reads it
  as the design.
- **Headers and titles never use an em dash or en dash.** They read as machine-written. Use the middle dot
  `·`, which the app already uses (`Passport · CHAI`), or rewrite the line. Covers screen titles, card
  titles, category labels and exported Markdown headings. Headings in existing docs (this file, HANDOFF,
  the checkpoints) were deliberately left alone; new docs follow the rule.
- Renaming a user-visible label that is also a stored value needs an alias for the old spelling. See
  `ExpenseCategories.canonical` — receipts saved before a rename still resolve.
- **Capitals.** Every label, pill, hint and each `·` segment starts with a capital letter
  (`Auto: SG region`, `DOB · Format`, `Unlocked · Will seal`). Exceptions: the keyboard's `space` key,
  units (`60 s`), file paths and identifiers. Stored strings written before the rule are capitalised at
  display with `DisplayText.capitalisedSegments`, never rewritten.
- **Dates read 12/MAR/1990** everywhere in the app (`FillFormats.display`, `Date.dvDisplay`). Storage and
  Markdown export stay ISO; the keyboard formats for the form it is filling.
- **Placeholders stay bare.** `Search`, never `Search documents…` and never with a glyph in front.
- Prose inside sentences is unaffected; a dash used as punctuation mid-sentence is fine.

## Conventions

- Field keys are camelCase strings shared by extractors, exporter, keyboard and redactor
  (`surname`, `passportNumber`, `nric`, `idNumber`, `pan`, `last4`, `merchant`, `total`, `partyA`…).
  Adding a field means updating `FillFormats.keys(for:)` if the keyboard should offer it.
- OCR confidence threshold is `OCRLine.lowConfidenceThreshold` (0.45). Vision's scale is coarse; do not "fix" by raising it.
- Export: `vault/<person>/<type>-<title>.md`, `vault/index.md`, `expenses.csv`. Markdown is the interchange
  format; the app mirror is always written, folder sync is optional.
- Tests live in `DocuVaultCore/Tests/`. OCR tests render text with CoreText (`TestImageFactory`).
- Bug reports arrive as screenshots, not prose — see “Bug reports by screenshot” above for the loop
  (confirm the bug whenever it is unclear, then fix, test, push, and tell him `git pull` then ⌘R).
