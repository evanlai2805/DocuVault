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
Later: summaries, Claude opt-in with redaction, chat over vault, business cards, translate, tables.
