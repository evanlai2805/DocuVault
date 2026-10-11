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
        XCTAssertTrue(md.hasPrefix("# Passport — Evan Lai\n"))
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
