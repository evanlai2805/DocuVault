import XCTest
import CryptoKit
@testable import DocuVaultCore

final class VaultCryptoTests: XCTestCase {
    func testRoundTrip() throws {
        let key = VaultCrypto.makeKey()
        let sealed = try VaultCrypto.seal("K1234567A", key: key)
        XCTAssertTrue(VaultCrypto.isSealed(sealed))
        XCTAssertFalse(VaultCrypto.isSealed(Data("K1234567A".utf8)))
        XCTAssertEqual(try VaultCrypto.openString(sealed, key: key), "K1234567A")
    }
    func testWrongKeyFails() throws {
        let sealed = try VaultCrypto.seal("secret", key: VaultCrypto.makeKey())
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: VaultCrypto.makeKey())) { e in
            XCTAssertEqual(e as? VaultError, .wrongKeyOrTampered)
        }
    }
    func testTamperFails() throws {
        let key = VaultCrypto.makeKey()
        var sealed = try VaultCrypto.seal(Data(repeating: 7, count: 100), key: key)
        sealed[sealed.count - 5] ^= 0xFF
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: key))
    }
    func testPlainDataIsNotSealed() {
        XCTAssertThrowsError(try VaultCrypto.open(Data("hello".utf8), key: VaultCrypto.makeKey())) { e in
            XCTAssertEqual(e as? VaultError, .notSealed)
        }
    }
    func testKeyDataRoundTrip() {
        let k = VaultCrypto.makeKey()
        let d = VaultCrypto.keyData(k)
        XCTAssertEqual(d.count, 32)
        XCTAssertEqual(VaultCrypto.keyData(VaultCrypto.key(from: d)!), d)
        XCTAssertNil(VaultCrypto.key(from: Data(count: 5)))
    }
    func testDifferentNoncePerSeal() throws {
        let key = VaultCrypto.makeKey()
        XCTAssertNotEqual(try VaultCrypto.seal("x", key: key), try VaultCrypto.seal("x", key: key))
    }
}

final class RetentionTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    let now = ISO8601DateFormatter().date(from: "2026-10-11T06:00:00Z")!

    func testExpiryAndStatus() {
        let captured = cal.date(byAdding: .day, value: -27, to: now)!
        let exp = Retention.expiryDate(capturedAt: captured, retentionDays: 30)!
        XCTAssertEqual(Retention.status(expiresAt: exp, now: now), .warning(daysLeft: 3))
        let fresh = Retention.expiryDate(capturedAt: now, retentionDays: 30)!
        XCTAssertEqual(Retention.status(expiresAt: fresh, now: now), .active(daysLeft: 30))
        let old = cal.date(byAdding: .day, value: -31, to: now)!
        XCTAssertEqual(Retention.status(expiresAt: Retention.expiryDate(capturedAt: old, retentionDays: 30), now: now), .due)
        XCTAssertEqual(Retention.status(expiresAt: nil, now: now), .none)
        XCTAssertNil(Retention.expiryDate(capturedAt: now, retentionDays: nil))
    }

    func testActions() {
        let exp = cal.date(byAdding: .day, value: 3, to: now)!
        if case .newExpiry(let d) = Retention.apply(.extend, currentExpiry: exp, now: now) {
            XCTAssertEqual(Retention.daysBetween(now, d!), 33)
        } else { XCTFail() }
        XCTAssertEqual(Retention.apply(.keep, currentExpiry: exp, now: now), .newExpiry(nil))
        XCTAssertEqual(Retention.apply(.deleteNow, currentExpiry: exp, now: now), .delete)
        // Extending an already-due document counts from today, not from the past expiry.
        let past = cal.date(byAdding: .day, value: -10, to: now)!
        if case .newExpiry(let d) = Retention.apply(.extend, currentExpiry: past, now: now) {
            XCTAssertEqual(Retention.daysBetween(now, d!), 30)
        } else { XCTFail() }
    }

    func testTombstone() {
        let line = Retention.tombstoneLine(title: "Director passport", type: .passport, owner: "Lee & Co", deletedAt: now, retentionDays: 30)
        XCTAssertEqual(line, "- ~~Director passport~~ · Passport · Lee & Co · deleted 2026-10-11 after 30 d")
    }
}

final class MarkdownExporterTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-11T06:00:00Z")!

    func sample() -> ExportDocument {
        let r = PassportExtractor.extract(lines: ClassifierTests.passport, now: now)
        return ExportDocument(title: "Evan Lai", owner: "Evan", ownerKind: .me, type: .passport, sensitive: true,
                              capturedAt: now, source: "camera", language: "en",
                              checksPassed: r.checksPassed, checksTotal: r.checksTotal, fields: r.fields,
                              notes: "Renew by 2030-05.", imageFileNames: ["passport_front.jpg"])
    }

    func testDocumentMarkdown() {
        let md = MarkdownExporter.markdown(for: sample())
        XCTAssertTrue(md.hasPrefix("# Passport · Evan Lai\n"))
        XCTAssertTrue(md.contains("owner: Evan"))
        XCTAssertTrue(md.contains("checks: 5/5 ✓"))
        XCTAssertTrue(md.contains("| Passport no."))
        XCTAssertTrue(md.contains("K1234567A"))
        XCTAssertTrue(md.contains("MRZ ✓"))
        XCTAssertTrue(md.contains("## Secondary"))
        XCTAssertTrue(md.contains("Place of birth"))
        XCTAssertTrue(md.contains("## Copy block\n"))
        XCTAssertTrue(md.contains("## Images\npassport_front.jpg"))
        XCTAssertTrue(md.contains("## Notes\nRenew by 2030-05."))
        // Secondary fields must not appear in the main table.
        let mainTable = md.components(separatedBy: "## Secondary").first!
        XCTAssertFalse(mainTable.contains("Place of birth"))
    }

    func testSummaryIsExported() {
        var d = sample()
        d.summary = DocumentSummary(language: "en", headline: "Passport ok", format: .bullets, body: ["Valid to 2031."], keyFacts: [], actions: [])
        let md = MarkdownExporter.markdown(for: d)
        XCTAssertTrue(md.contains("## Summary\n\n**Passport ok**\n\n- Valid to 2031."))
    }

    func testMissingAndPipesAreSafe() {
        var d = sample()
        d.fields = [ExtractedField(key: "a", labelEN: "A", value: "x|y", check: .ocr),
                    ExtractedField(key: "b", labelEN: "B", value: "", check: .missing)]
        let md = MarkdownExporter.markdown(for: d)
        XCTAssertTrue(md.contains("x¦y"))
        XCTAssertTrue(md.contains("| —"))
        XCTAssertTrue(md.contains("missing"))
    }

    func testIndex() {
        let rows = [
            MarkdownExporter.IndexRow(owner: "Evan", kind: .me, title: "Passport", type: .passport, expiry: "2031-02-28", checks: "5/5", path: "vault/Evan/passport-Passport.md"),
            MarkdownExporter.IndexRow(owner: "Lee & Co", kind: .client, title: "Director passport", type: .passport, expiry: nil, checks: "4/5", path: "vault/Lee-Co/passport-Director-passport.md"),
        ]
        let tomb = [Retention.tombstoneLine(title: "BizFile", type: .other, owner: "Lee & Co", deletedAt: now, retentionDays: 30)]
        let md = MarkdownExporter.index(rows: rows, tombstones: tomb, generatedAt: now)
        XCTAssertTrue(md.contains("## Evan (Me)"))
        XCTAssertTrue(md.contains("## Lee & Co (Client)"))
        XCTAssertTrue(md.contains("| Passport | Passport | 2031-02-28 | 5/5 | [vault/Evan/passport-Passport.md](vault/Evan/passport-Passport.md) |"))
        XCTAssertTrue(md.contains("## Deleted (retention)\n- ~~BizFile~~"))
    }

    func testRelativePathAndSlug() {
        XCTAssertEqual(MarkdownExporter.relativePath(owner: "Lee & Co", type: .passport, title: "Director passport"), "vault/Lee-Co/passport-Director-passport.md")
        XCTAssertEqual(MarkdownExporter.slug("租赁合同 — 西安某某"), "租赁合同-西安某某")
        XCTAssertEqual(MarkdownExporter.slug("///"), "untitled")
    }

    func testCSVAppend() {
        let row = "2026-10-10,SINGAPORE AIRLINES,Flights,SGD,412.00,32.00,4417,7XK2PQ"
        let one = MarkdownExporter.appendCSV(existing: "", row: row)
        XCTAssertEqual(one, MarkdownExporter.csvHeader + "\n" + row + "\n")
        let twice = MarkdownExporter.appendCSV(existing: one, row: row)
        XCTAssertEqual(twice, one)                                   // duplicate skipped
        let second = MarkdownExporter.appendCSV(existing: one, row: "2026-10-11,Grab,Taxi & Ride-hail,SGD,18.50,,4417,")
        XCTAssertEqual(second.split(separator: "\n").count, 3)
    }
}

final class FillFormatsTests: XCTestCase {
    func testDates() {
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .iso), "1999-04-12")
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .dmySlash), "12/04/1999")
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .mdySlash), "04/12/1999")
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .dMonY), "12 Apr 1999")
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .digitsDMY), "12041999")
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .digitsYMD), "19990412")
        XCTAssertEqual(FillFormats.date("长期", style: .dmySlash), "长期")
    }
    func testCardNumbers() {
        XCTAssertEqual(FillFormats.cardNumber("4111 1111 1111 1111", spaced: false), "4111111111111111")
        XCTAssertEqual(FillFormats.cardNumber("4111111111111111", spaced: true), "4111 1111 1111 1111")
        XCTAssertEqual(FillFormats.cardNumber("378282246310005", spaced: true), "3782 822463 10005")
    }
    func testExpiry() {
        XCTAssertEqual(FillFormats.expiry("09/29", style: .mmSlashYY), "09/29")
        XCTAssertEqual(FillFormats.expiry("09/29", style: .mmSlashYYYY), "09/2029")
        XCTAssertEqual(FillFormats.expiry("9/2029", style: .mmyy), "0929")
    }
    func testPostcode() {
        XCTAssertEqual(FillFormats.postcode(from: "123 BEDOK NORTH ST 1 #05-123 SINGAPORE 460123"), "460123")
        XCTAssertEqual(FillFormats.postcode(from: "Blk 10 Jurong West 640010"), "640010")
        XCTAssertNil(FillFormats.postcode(from: "陕西省西安市雁塔区科技路10号"))
    }
    func testKeySpecs() {
        XCTAssertEqual(FillFormats.keys(for: .bankCard).first?.fieldKey, "pan")
        XCTAssertEqual(FillFormats.keys(for: .bankCard).first { $0.fieldKey == "cvv" }?.kind, .holdOnly)
        XCTAssertTrue(FillFormats.keys(for: .chinaID).contains { $0.label == "姓名" })
        XCTAssertTrue(FillFormats.keys(for: .chinaID).contains { $0.fieldKey == "namePinyin" })
        XCTAssertTrue(FillFormats.keys(for: .receipt).isEmpty)
        XCTAssertLessThan(FillFormats.order(.bankCard), FillFormats.order(.passport))
    }
}

final class FillInferenceTests: XCTestCase {
    typealias C = FillInference.Context
    func testBirthdateComponents() {
        XCTAssertEqual(FillInference.date(C(contentType: "birthdateDay")).value, .component(.day))
        XCTAssertEqual(FillInference.date(C(contentType: "birthdateYear")).value, .component(.year))
        XCTAssertEqual(FillInference.component(.month, of: "1999-04-12"), "04")
        XCTAssertEqual(FillInference.component(.year, of: "1999-04-12"), "1999")
    }
    func testNumberPad() {
        XCTAssertEqual(FillInference.date(C(keyboard: .numeric, region: "SG")).value, .full(.digitsDMY))
        XCTAssertEqual(FillInference.date(C(keyboard: .numeric, region: "CN")).value, .full(.digitsYMD))
        XCTAssertEqual(FillInference.expiry(C(keyboard: .numeric)).value, .mmyy)
    }
    func testSeparatorsNearCursor() {
        XCTAssertEqual(FillInference.date(C(before: "2026-", region: "SG")).value, .full(.iso))
        XCTAssertEqual(FillInference.date(C(after: "/", region: "SG")).value, .full(.dmySlash))
        XCTAssertEqual(FillInference.date(C(after: "/", region: "US")).value, .full(.mdySlash))
        XCTAssertEqual(FillInference.date(C(before: "DD/MM/YYYY ", region: "US")).value, .full(.dmySlash))
    }
    func testRegionDefaults() {
        XCTAssertEqual(FillInference.date(C(region: "SG")).value, .full(.dmySlash))
        XCTAssertEqual(FillInference.date(C(region: "CN")).value, .full(.iso))
        XCTAssertEqual(FillInference.date(C(region: "US")).value, .full(.mdySlash))
        XCTAssertEqual(FillInference.date(C(region: "SG")).reason, "SG region")
    }
    func testExpiryHints() {
        XCTAssertEqual(FillInference.expiry(C(after: " (MM/YYYY)")).value, .mmSlashYYYY)
        XCTAssertEqual(FillInference.expiry(C()).value, .mmSlashYY)
    }
    func testCardSpacing() {
        XCTAssertFalse(FillInference.cardSpaced(C()))
        XCTAssertTrue(FillInference.cardSpaced(C(before: "4111 1111 ")))
        XCTAssertFalse(FillInference.cardSpaced(C(keyboard: .numeric, before: "4111 1111 ")))
    }

    // MARK: Category names after em dashes left the UI

    func testCategoryNamesCarryNoEmDash() {
        XCTAssertTrue(ExpenseCategories.names.allSatisfy { !$0.contains("—") },
                      "category labels must not contain an em dash")
        XCTAssertTrue(ExpenseCategories.names.contains("Travel · Other"))
    }

    func testOldCategoryNameStillResolves() {
        // A receipt saved before the rename carries the old spelling.
        XCTAssertEqual(ExpenseCategories.canonical("Travel — Other"), "Travel · Other")
        XCTAssertEqual(ExpenseCategories.category(named: "Meals — Business")?.group, "Food")
        XCTAssertEqual(ExpenseCategories.category(named: "Meals · Business")?.group, "Food")
    }

    func testCanonicalLeavesUnknownNamesAlone() {
        XCTAssertEqual(ExpenseCategories.canonical("Flights"), "Flights")
        XCTAssertEqual(ExpenseCategories.canonical("Some — Thing"), "Some — Thing")
        XCTAssertNil(ExpenseCategories.category(named: "Not a category"))
    }
}
