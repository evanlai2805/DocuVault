import XCTest
@testable import DocuVaultCore

/// Checkpoint 20: every document on the keyboard, Recents by last touched, the Documents tab's groups,
/// keys for regular documents, text lines, and field hints.
final class KeyboardHomeTests: XCTestCase {

    private let ben = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Rows without a person

    func testRowWithoutPersonShowsDetailOnTheRight() {
        let r = FillEntry(title: "Starbucks", personName: "", personID: nil, kind: .document(UUID()), detail: "14/OCT", type: .receipt)
        XCTAssertNil(r.personID)
        XCTAssertEqual(r.trailing, "14/OCT")
        let p = FillEntry(title: "Passport", personName: "Ben Ong", personID: ben, kind: .document(UUID()), detail: "ignored")
        XCTAssertEqual(p.trailing, "Ben Ong")
    }

    func testDetailPerType() {
        let now = t0
        XCTAssertEqual(FillPicker.detail(type: .receipt, fields: [:], addedAt: now, now: now), FillPicker.shortDate(now, now: now))
        XCTAssertEqual(FillPicker.detail(type: .businessCard, fields: ["company": "Harbour Law LLP"], addedAt: now), "Harbour Law LLP")
        XCTAssertEqual(FillPicker.detail(type: .contract, fields: ["partyA": "Ben Ong", "partyB": "Lim Properties"], addedAt: now), "Lim Properties")
        XCTAssertEqual(FillPicker.detail(type: .letter, fields: ["partyA": "IRAS"], addedAt: now), "IRAS")
        XCTAssertNil(FillPicker.detail(type: .other, fields: [:], addedAt: now))
        XCTAssertNil(FillPicker.detail(type: .businessCard, fields: ["company": ""], addedAt: now))
    }

    func testShortDateDropsTheYearOnlyWhenItIsThisYear() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 14; c.hour = 12
        let cal = Calendar(identifier: .gregorian)
        let oct14 = cal.date(from: c)!
        c.year = 2025
        let lastYear = cal.date(from: c)!
        XCTAssertEqual(FillPicker.shortDate(oct14, now: oct14), "14/OCT")
        XCTAssertEqual(FillPicker.shortDate(lastYear, now: oct14), "14/OCT/2025")
    }

    func testSharedKeyWithoutPersonIsStable() {
        XCTAssertEqual(FillPicker.key(personID: nil, kind: .shared), "shared:none")
    }

    func testSearchFindsANoPersonRowByItsDetail() {
        let card = FillEntry(title: "Daniel Koh", personName: "", personID: nil, kind: .document(UUID()), detail: "Harbour Law LLP", type: .businessCard)
        let other = FillEntry(title: "Passport", personName: "Ben Ong", personID: ben, kind: .document(UUID()))
        XCTAssertEqual(FillPicker.search([other, card], query: "harb").map(\.entry.title), ["Daniel Koh"])
    }

    // MARK: Recents

    func testRecentsOrderByTheLaterOfCaptureAndFill() {
        let passport = FillEntry(title: "Passport", personName: "Ben Ong", personID: ben, kind: .document(UUID()), addedAt: t0)
        let receipt = FillEntry(title: "Starbucks", personName: "", personID: nil, kind: .document(UUID()), addedAt: t0.addingTimeInterval(3600))
        let contact = FillEntry(title: "Contact details", personName: "Ben Ong", personID: ben, kind: .shared)
        // Nothing filled yet: newest capture first, never-touched contact details last.
        XCTAssertEqual(FillPicker.recents([contact, passport, receipt], lastUsed: [:]).map(\.title), ["Starbucks", "Passport", "Contact details"])
        // Filling the old passport later brings it above the receipt.
        let used = [passport.id: t0.addingTimeInterval(7200)]
        XCTAssertEqual(FillPicker.recents([contact, passport, receipt], lastUsed: used).map(\.title), ["Passport", "Starbucks", "Contact details"])
        // Filling contact details gives them a place too.
        let used2 = [contact.id: t0.addingTimeInterval(9000)]
        XCTAssertEqual(FillPicker.recents([passport, receipt, contact], lastUsed: used2).first?.title, "Contact details")
    }

    // MARK: Documents tab

    func testGroupsFollowTheCategoryOrderAndSkipEmptyOnes() {
        let rows = [
            FillEntry(title: "Starbucks", personName: "", personID: nil, kind: .document(UUID()), type: .receipt),
            FillEntry(title: "Passport", personName: "Ben Ong", personID: ben, kind: .document(UUID()), type: .passport),
            FillEntry(title: "Contact details", personName: "Ben Ong", personID: ben, kind: .shared),
            FillEntry(title: "NRIC", personName: "Ben Ong", personID: ben, kind: .document(UUID()), type: .nric),
            FillEntry(title: "Booking", personName: "", personID: nil, kind: .document(UUID()), type: .other),
        ]
        let g = FillPicker.groups(rows)
        XCTAssertEqual(g.map(\.name), ["Contact details", "Passports", "ID cards", "Receipts", "Notes and other"])
        XCTAssertEqual(g.first { $0.name == "ID cards" }?.entries.map(\.title), ["NRIC"])
    }

    // MARK: Keys

    func testRegularDocumentsHaveKeys() {
        XCTAssertEqual(FillFormats.keys(for: .receipt).map(\.fieldKey), ["merchant", "date", "total", "tax", "reference", "paymentMethod"])
        XCTAssertEqual(FillFormats.keys(for: .contract).map(\.fieldKey), ["title", "partyA", "partyB", "effectiveDate", "expiryDate", "governingLaw"])
        XCTAssertEqual(FillFormats.keys(for: .letter).map(\.fieldKey), FillFormats.keys(for: .contract).map(\.fieldKey))
        XCTAssertEqual(FillFormats.keys(for: .businessCard).map(\.fieldKey), ["name", "title", "company", "phone", "email", "website"])
        XCTAssertTrue(FillFormats.keys(for: .other).isEmpty)
        XCTAssertEqual(FillFormats.keys(for: .receipt).first { $0.fieldKey == "date" }?.kind, .date)
    }

    func testEveryKeyMatchesAFieldTheExtractorWrites() {
        // Keys must name the field keys the extractors store, or the key stays grey forever.
        let receipt = ReceiptExtractor.extract(lines: ["STARBUCKS", "14/10/2026", "TOTAL 12.50", "GST 1.03", "VISA ****4421", "Ref: A1B2"])
        let keys = Set(receipt.fields.map(\.key))
        for k in ["merchant", "total"] { XCTAssertTrue(keys.contains(k), "receipt extractor wrote no \(k)") }
        let card = BusinessCardExtractor.extract(lines: ["Daniel Koh", "Partner", "Harbour Law LLP", "+65 6123 4567", "daniel@harbourlaw.sg", "www.harbourlaw.sg"])
        let cardKeys = Set(card.fields.map(\.key))
        for k in ["name", "company", "email", "website"] { XCTAssertTrue(cardKeys.contains(k), "business card extractor wrote no \(k)") }
    }

    // MARK: Text lines

    func testLinesTrimAndSkipBlanks() {
        XCTAssertEqual(FillLines.lines(from: "  Booking reference: K7Q2LM \n\n SQ 322 \n"), ["Booking reference: K7Q2LM", "SQ 322"])
        XCTAssertEqual(FillLines.lines(from: String(repeating: "x\n", count: 200)).count, 80)
    }

    func testSplitLabelAndValue() {
        XCTAssertEqual(FillLines.split("Booking reference: K7Q2LM")?.label, "Booking reference")
        XCTAssertEqual(FillLines.split("Booking reference: K7Q2LM")?.value, "K7Q2LM")
        XCTAssertEqual(FillLines.split("订单号：88231")?.value, "88231")
        XCTAssertNil(FillLines.split("SQ 322 · 23:35".replacingOccurrences(of: ":", with: "")))
        XCTAssertNil(FillLines.split("Note:"))
        XCTAssertNil(FillLines.split(String(repeating: "a", count: 40) + ": b"))
    }

    // MARK: Field hints

    func testHintsMapToTargetsAndKeys() {
        XCTAssertEqual(FillInference.hint(contentType: "emailAddress")?.target, .contact)
        XCTAssertEqual(FillInference.hint(contentType: "emailAddress")?.keys, ["email"])
        XCTAssertEqual(FillInference.hint(contentType: "organizationName")?.target, .businessCard)
        XCTAssertEqual(FillInference.hint(contentType: "creditCardNumber")?.keys, ["pan"])
        XCTAssertEqual(FillInference.hint(contentType: "birthdate")?.target, .passport)
        XCTAssertNil(FillInference.hint(contentType: nil))
        XCTAssertNil(FillInference.hint(contentType: "oneTimeCode"))
    }
}
