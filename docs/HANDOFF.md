# DocuVault — handoff (12 Oct 2026)

Built in a Claude cloud session from 11 Oct 2026, verified on GitHub Actions, first installed on Evan's
iPhone 17 Pro on 12 Oct 2026. This file is the memory of that session. Keep it current: when a decision
changes or a phase lands, edit the matching section in the same commit.

## 1. Status

| Phase | What | State |
|---|---|---|
| 1 | Core package + checkers (MRZ, Luhn, NRIC, 身份证, TextRules) | Done, tested |
| 2 | Capture: camera, Photos, Files, clipboard, PDF; pages editor; Vision OCR | Done, on device |
| 3 | Classify + extract + review screen (pills, main/secondary) | Done, on device |
| 4 | Vault: AES-GCM sealing, Face ID key, people, retention, .md export, expenses.csv | Done, Face ID on device **unverified** |
| 5 | Keyboard extension: fill from vault, formats, inference | Done; Face ID from the keyboard **unverified** |
| 6 | Summaries: Apple Foundation Models, Qwen3-4B via MLX for Chinese, Writing Tools | Done; quality **unverified** on device |
| 7 | Claude opt-in: Redactor, CloudGate, approval sheet, send log, API key | Done; first live send **unverified** |
| 7a | Batch import: one document per image, queued review/save, merge/split | Done 12 Oct |

CI: `core-tests.yml` (123 tests) and `app-build.yml` (Simulator build incl. MLX) both green at `66963c1`.

Device fixes already shipped on 12 Oct: environment injection for presented sheets (crash on save),
owner picker wrapping, identity/card/receipt titles from fields, keyboard lock row rendering,
press-and-hold backspace.

## 2. Decisions Evan made (by checkpoint)

Checkpoint 1 — screens
- Vault values: both fill (keyboard) and copy. Plain-text export without warnings. Client docs auto-expire.
- Receipts: CSV export and in-app copy; always keep a copy in the app.
- Cloud: allowed only for non-sensitive documents, explicit approval on every send, no "always allow".

Checkpoint 2 — schemas
- Race and blood group go in a separate "Secondary" section, stored apart from the main block.
- Encryption stays but must be invisible: "locked notes" UX behind Face ID.
- Pinyin varies per person. Ask when unsure. Surname is its own field. Names follow NRIC/passport.
- All categories and type names display in English.

Checkpoint 3 — architecture
- App name DocuVault. Bundle `com.evanlai.docuvault`, keyboard `.keyboard`, App Group `group.com.evanlai.docuvault`.
- Client retention: 30 days, warn 3 days before, options extend 1 month / keep / delete now.
- Repo: github.com/evanlai2805/DocuVault, Evan has push access, CI on every push.

Checkpoint 4 — capture
- Traditional Chinese OCR on. Handwriting included, low-confidence lines marked. PDFs use the text layer when present.

Checkpoint 5 — design
- Flighty is the reference: fonts, gradient cards, glass pills, light theme. Scan and Search in a
  separate right pill (scan left, search right), colour coded. No layered sheet UI. Cards coloured by
  state, not type. Layout stays function-first for a scanner/vault app.

Checkpoint 6 — review
- Pinyin surname/given-name split is a selection widget, not a toggle.
- Expense categories: a comprehensive list modelled on expense apps (26 categories).
- Saving is allowed when a check fails (pill shows red).

Checkpoint 7 — vault
- Folder sync is a toggle. Page images off by default in export. Shared fields per person. Keep tombstones.

Checkpoint 8 — keyboard
- Card number: tap inserts without spaces, hold inserts spaced. Dates: the app infers the format the
  field needs. Chinese fields offer both keys. Keyboard stays open after an insert.

Checkpoint 9 — summaries
- Auto-summarise contracts and letters on save. Format: model decides, remembered per type, asks when unsure.
- Mixed-language document: ask which language. Qwen (download) for Chinese, Apple model as fallback.

Checkpoint 10 — Claude opt-in (built with these defaults; Evan has not yet answered Q1–Q6)
- IDs/contacts always redacted and locked; names and amounts on by default; dates off. Restore on reply.
- Entry points: "Summarise with Claude…", "Ask Claude about this…", "Use Claude instead" on failure. Never automatic.
- Model default `claude-sonnet-5-5`; Haiku and Opus selectable. Cost shown as an estimate.
- API key pasted in Settings, Keychain, this device only, masked. Log keeps the redacted text, 90 days.
- Chinese documents also offered.

12 Oct — batch import
- Q1 (a): one document per image for Photos and Files. PDFs stay one document each. Camera stays one document.
- Q2: after save or Skip, the next document's review opens with "n of N". Last save returns to the library.

## 3. Open device validations (do these next, in order)

1. Scan a real passport: MRZ pill green? Title "Passport · SURNAME"? Owner picker readable?
2. Scan NRIC, a receipt, an English letter, a Chinese contract. Report misreads with screenshots.
3. Vault: does Face ID prompt on "Save to Vault"? Does the vault tab unlock? Auto-lock after 60 s in background?
4. Keyboard: enable in Settings with Full Access. Tap the Face ID key. If no prompt appears, keyboard
   extensions may be blocked from LocalAuthentication; the fallback is to unlock in the app and share the
   session via the App Group for a short window (design needed — ask Evan).
5. Summaries: Apple model availability message; summary quality on the English letter; Qwen download
   size and speed on the Chinese contract; memory behaviour.
6. Claude: paste a key, send the English letter, confirm the log row, the restored placeholders and the cost.
7. Export: folder picker bookmark survives relaunch? `vault/index.md` correct?
8. Checkpoint 10 questions Q1–Q6 (in `docs/checkpoints/checkpoint10_cloud.html`) still need answers.

## 4. Known unknowns and risks

- Vision confidence values are coarse (≈0.5 for clean text). Threshold 0.45 was set from CI renders, not real scans.
- `#huggingFaceLoadModelContainer` macro needs "Trust & Enable" once in Xcode; CI passes `-skipMacroValidation`.
- `mlx-swift` resolved to 0.31.6 on both CI and Evan's Mac and built fine with Swift 6.2; the pin comment in
  `project.yml` about Swift 6.3 may be stale. Re-test before bumping `mlx-swift-lm` past 3.31.x.
- Price table in `CloudCost.models` is a placeholder list price; check against the console before relying on it.
- `Redactor` Chinese name rules are heuristic (role words, honorifics, company suffixes). Over-redaction is the
  safe failure; under-redaction of a bare 2-char name mid-sentence is possible.

## 5. Roadmap (not started)

- TestFlight: GitHub Actions archive + upload on tag, needs an App Store Connect API key.
- Chat over the library/vault: on-device embeddings + local model; vault answers only while unlocked.
- Extras: business card → Contacts, zh↔en translate, table → CSV, batch → searchable PDF.
- Share-sheet extension so PDFs and images can be sent to DocuVault from other apps.

## 6. How to report a bug to Claude Code

One line per bug, with a screenshot when visual: "Where — what happened — what you expected."
Claude Code fixes, runs `scripts/test-core.sh`, pushes, and tells you `git pull` then ⌘R (or runs
`scripts/run-device.sh` itself when the phone is connected).
