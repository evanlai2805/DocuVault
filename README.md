# DocuVault

iOS document scanner with on-device OCR (English + Simplified Chinese), a Face ID vault for
sensitive documents, and a local AI layer for summaries and extraction.

Target: iPhone 17 Pro and newer, iOS 26. Personal tool, not App Store.

## Layout

```
DocuVaultCore/        Swift package · shared by app and keyboard · no UI
  Sources/DocuVaultCore/
    Models/           DocumentType, FieldCheck, ExtractedField, PersonKind, RetentionPolicy
    Checkers/         MRZ (passport), CardCheck (Luhn + brand), NRIC (SG), ChinaID (身份证), TextRules
    Summary/          SummarySpec (language, format, STE, chunking, grounding), SummaryJSON
    Cloud/            Redactor (placeholders in/out), CloudGate (which docs may ever be sent), CloudCost
  Tests/              XCTest suite with ICAO specimen and published samples
DocuVault/            app target (Phase 2+)
DocuVaultKeyboard/    custom keyboard extension (Phase 5)
docs/checkpoints/     throwaway HTML mocks reviewed before each phase
```

## Identifiers

- App: `com.evanlai.docuvault`
- Keyboard: `com.evanlai.docuvault.keyboard`
- App Group: `group.com.evanlai.docuvault`

## Phase 1 — run the tests

```bash
cd DocuVaultCore
swift test
```

Or open `DocuVaultCore/Package.swift` in Xcode and press ⌘U.

Design rule: anything a checksum can verify is checked in code, not by a model.
The model only handles layout and language.

## Phases

1. Core + checkers (this commit)
2. Capture + OCR
3. Classify + extract + review screen
4. Vault + .md export + receipts.csv
5. Keyboard extension
6. Summaries: Apple Foundation Models, Qwen3-4B via MLX for Chinese, Writing Tools
7. Claude opt-in: per-send approval sheet, code-side redaction with restore, send log; never for vault documents
Later: chat over vault, business cards, translate, tables.

## Cloud rules (Phase 7)

- `CloudGate.allows` is false for vault documents, identity and payment types, receipts and business cards. The UI builds no entry point and `CloudService.send` refuses too.
- IDs, card numbers, phones and emails are always redacted. Names, amounts and dates are per-send toggles; placeholders like `[NAME 1]` or `[AMOUNT 2 SGD]` are restored on the phone from the reply.
- The approval sheet is the only path to the network. No "always allow" preference exists.
- Every outcome is logged (`StoredCloudSend`): sent, failed, or cancelled; optionally with the exact redacted text.
- The API key sits in the Keychain, this device only. Removing it removes every Claude option.
